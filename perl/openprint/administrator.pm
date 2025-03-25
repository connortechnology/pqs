use strict;
use warnings;
package openprint::administrator;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*param = \%openprint::param;
*session = \%openprint::session;

sub index {
} # end sub index

sub system {
  if ( $param{action} and $openprint::User->type() eq 'A' ) {
    if ( $param{action} eq 'shutdown' ) {
      `/bin/systemctl poweroff -i`;
    } elsif ( $param{action} eq 'reboot' ) {
      $log->debug("Executing /bin/systemctl reboot -i");
      $_ = `/bin/systemctl reboot -i 2>&1`;
      $log->debug($_);
    } else {
      $variable{error} .= "Unknown action $param{action}<br/>";
    }
  } # end if action and admin
} # end sub system

1;
__END__
