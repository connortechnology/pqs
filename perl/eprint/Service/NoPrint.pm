package eprint::Service::NoPrint;
use strict;
use warnings;

use Date::Calc        qw(Delta_Days Today Add_Delta_YM);
use List::Util        qw(max);
use eprint::project   qw(:common :pricing);
use eprint::equipment ();

require configuration;

sub munge {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
   
}

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;


    return 'calculated';
}


1;
