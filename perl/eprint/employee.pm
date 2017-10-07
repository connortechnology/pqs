package eprint::employee;

use strict;
require eprint::user;

require misc;
use sql ();

sub user_edit {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ( $r->param('btnFunction') eq 'Save' ) {

        my $error = "";
        $error .= "Password fields do not match.<br>" if $r->param('txtPassword') ne $r->param('txtVerifyPassword');
        $error .= "First Name cannot be blank.<br>" if $r->param('txtFirstName') eq '';
        $error .= "Last Name cannot be blank.<br>" if $r->param('txtLastName') eq '';
        $error .= "You must select a Salutation.<br>" if $r->param('rdbSalutation') eq '';
        $error .= "Phone cannot be blank.<br>" if $r->param('txtPhone') eq '';
        $error .= "Email Cannot be blank.<br>" if $r->param('txtEmail') eq '';
        if ( $error ne '' ) {
            return misc::error( $log, $dbh, $variable, "Bad Field", $error);
        } # end if

		eprint::user::save( $r, $log, $dbh, $variable, $$variable{'user_id'} );
    } # end if

    eprint::user::load( $log, $dbh, $$variable{'user_id'}, $variable );

    $$variable{'rdbMailingList'.$$variable{'rdbMailingList'}} = 'CHECKED';
    $$variable{'rdbSalutation'.$$variable{'rdbSalutation'}} = 'CHECKED';

} # end sub user_edit


1;

__END__
