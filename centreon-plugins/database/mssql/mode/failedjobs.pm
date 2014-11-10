################################################################################
# Copyright 2005-2013 MERETHIS
# Centreon is developped by : Julien Mathis and Romain Le Merlus under
# GPL Licence 2.0.
# 
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation ; either version 2 of the License.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along with 
# this program; if not, see <http://www.gnu.org/licenses>.
# 
# Linking this program statically or dynamically with other modules is making a 
# combined work based on this program. Thus, the terms and conditions of the GNU 
# General Public License cover the whole combination.
# 
# As a special exception, the copyright holders of this program give MERETHIS 
# permission to link this program with independent modules to produce an executable, 
# regardless of the license terms of these independent modules, and to copy and 
# distribute the resulting executable under terms of MERETHIS choice, provided that 
# MERETHIS also meet, for each linked independent module, the terms  and conditions 
# of the license of that module. An independent module is a module which is not 
# derived from this program. If you modify this program, you may extend this 
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
# 
# For more information : contact@centreon.com
# Authors : Kevin Duret <kduret@merethis.com>
#
####################################################################################

package database::mssql::mode::failedjobs;

use base qw(centreon::plugins::mode);

use strict;
use warnings;

my %states = (
    0 => 'failed',
    1 => 'success',
    2 => 'Retry',
    3 => 'Canceled',
    4 => 'Running',
);

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "filter:s"                => { name => 'filter', },
                                  "skip"                    => { name => 'skip', },
                                  "warning:s"               => { name => 'warning', },
                                  "critical:s"              => { name => 'critical', },
                                  "lookback:s"              => { name => 'lookback', },
                                });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);
}

sub run {
    my ($self, %options) = @_;
    # $options{sql} = sqlmode object
    $self->{sql} = $options{sql};

    $self->{output}->output_add(severity => 'OK',
                                short_msg => "All jobs are ok.");

    $self->{sql}->connect();

    my $count = 0;
    my $count_failed = 0;

    my $query = "SELECT j.[name] AS [JobName], run_status, h.run_date AS LastRunDate, h.run_time AS LastRunTime,
                 CASE
                    WHEN h.[run_date] IS NULL OR h.[run_time] IS NULL THEN NULL
                    ELSE datediff(Minute, CAST(
                        CAST(h.[run_date] AS CHAR(8))
                        + ' '
                        + STUFF(
                            STUFF(RIGHT('000000' + CAST(h.[run_time] AS VARCHAR(6)),  6)
                                , 3, 0, ':')
                                , 6, 0, ':')
                        AS DATETIME), current_timestamp)
                 END AS [MinutesSinceStart]
                 FROM msdb.dbo.sysjobhistory h 
                 INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id 
                 WHERE j.enabled = 1 
                 AND h.instance_id IN (SELECT MAX(h.instance_id) 
                 FROM msdb.dbo.sysjobhistory h GROUP BY (h.job_id))";
    $self->{sql}->query(query => $query);
    my $result = $self->{sql}->fetchall_arrayref();
    foreach my $row (@$result) {
        next if (defined($self->{option_results}->{filter}) && $$row[0] !~ /$self->{option_results}->{filter}/);
        next if (defined($self->{option_results}->{lookback}) && $$row[4] > $self->{option_results}->{lookback});
        $count++;
        my $job_name = $$row[0];
        my $run_status = $$row[1];
        my $run_date = $$row[2];
        $run_date =~ s/(\d{4})(\d{2})(\d{2})/$1-$2-$3/;
        my $run_time = $$row[3];
        $self->{output}->output_add(long_msg => sprintf("Job '%s' status %s [Date : %s] [Runtime : %ss]", $job_name, $states{$run_status}, $run_date, $run_time));
        if ($run_status == 0) {
            $count_failed++;
        }
    }

    my $exit_code = $self->{perfdata}->threshold_check(value => $count_failed, threshold => [ { label => 'critical', 'exit_litteral' => 'critical' }, { label => 'warning', exit_litteral => 'warning' } ]);
    if(!defined($self->{option_results}->{skip}) && $count == 0) {
        $self->{output}->output_add(severity => 'Unknown',
                                    short_msg => "No job found.");
    } elsif (!$self->{output}->is_status(value => $exit_code, compare => 'ok', litteral => 1)) {
        $self->{output}->output_add(severity => $exit_code,
                                    short_msg => sprintf("%d failed job(s)", $count_failed));
    }

    $self->{output}->perfdata_add(label => 'failed_jobs',
                                  value => $count_failed,
                                  min => 0,
                                  max => $count);

    $self->{output}->display();
    $self->{output}->exit();
}

1;

__END__

=head1 MODE

Check MSSQL failed jobs.

=over 8

=item B<--filter>

Filter job.

=item B<--skip>

Skip error if no job found.

=item B<--warning>

Threshold warning.

=item B<--critical>

Threshold critical.

=item B<--lookback>

Check job history in minutes.

=back

=cut
