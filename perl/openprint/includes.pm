use strict;
package openprint::includes;

use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub _states {
} # end sub _states

sub _provinces {
} # end sub _provinces

sub _opinion_button {
	my $Object_Type = openprint::Object_Type->find_one('name'=>$param{object_type});
	if ( ! $Object_Type ) {
		$log->error('Object type not found : ' . $param{object_type} );
		$variable{error} .= 'Unable to opinion. Please try again later';
		return;
	} # end if
	my $Object = $variable{Object} = $Object_Type->Object( $param{object_id} );
	$Object->toggle_Opinion( $param{opinion_type_id} );
} # end sub opinion_button

sub _opinions {
	my $Object_Type = openprint::Object_Type->find_one('name'=>$param{object_type});
	if ( ! $Object_Type ) {
		$log->error('Object type not found : ' . $param{object_type} );
		$variable{error} .= 'Unable to load opinions. Please try again later';
		return;
	} # end if
	my $Object = $variable{Object} = $Object_Type->Object( $param{object_id} );
	$Object->toggle_Opinion( $param{opinion_type_id} );
} # end sub _opinions

sub _captcha {
} # end sub _captcha

sub _privacy_name {
} # end sub _privacy_name
sub _privacy_users {
	my $Privacy = $variable{Privacy} = new openprint::Privacy( $param{privacy_id} );
	if ( $param{action} eq 'add' ) {
		$Privacy->user_id( [ sets::union( @{$Privacy->user_id()}, $param{user_id} ) ] );
		$variable{error} .= $Privacy->save();	
	} elsif ( $param{action} eq 'set' ) {
		$Privacy->user_id( $param{user_id} );
	} else {
		$log->error("Unknown action in _privacy_users");
	} # end if
}

sub _users {
} # end sub _users

sub _comments {
	my $Object = $variable{Object} = $param{object_type}->new( $param{object_id} );
	if ( $param{text} ) {
		if ( ! openprint::Comment->find_one(
			'user_id'	=>	$session{user_id},
			'text'		=>	$param{text},
			'object_id'	=>	$Object->id(),
			'object_type'	=>	$param{object_type}
			) ) {

			my $approved = 0;
			if ( $session{user_type} eq 'A' or ( $session{user_id} == $Object->created_by() ) ) {
				$approved = 1;
			} # endif

			$variable{error} .= new openprint::Comment()->save({
					'text'			=>	$param{text},
					'object_type'	=>	$param{object_type},
					'object_id'		=>	$Object->id(),
					'approved'		=>	$approved,
					});
		} # end if comment already exists
	} elsif ( $param{action} eq 'approve' ) {
		if ( $session{user_type} eq 'A' or $session{user_id} == $$Object->created_by() ) {
			my $Comment = openprint::Comment->find_one('object_id'=>$$Object{id}, 'object_type'=>$param{object_type}, 'id'=>$param{comment_id} );
			if ( $Comment ) {
				$Comment->save({'approved'=>1});
			} else {
				$variable{error} .= 'Comment not found.';
			} # end if
		} else {
			$variable{error} .= 'You are not authorized to approve this comment.';
		} # end if
	} elsif ( $param{action} eq 'delete' ) {
		my $Comment = new openprint::Comment( $param{comment_id} );
		if ( $Comment->can_delete() ) {
			$Comment->delete();
		} else {
			$variable{error} .= 'You do not have the right to delete that comment.';
		} # end if
	} # end if
} # end sub _comments
sub _user_autocomplete {
} # end sub _user_autocomplete
sub _equipment {
} # end sub _equipment
sub _products_ddm {
} # end sub _products_ddm

sub _address_ddm {
	require openprint::Address;
} # end sub _addres_ddm

sub _company_ddm {
} # end sub _company_ddm

sub _logs_contents {
	my $Object_Type = new openprint::Object_Type( $param{object_type_id} );
	$variable{Object} = $Object_Type->Object( $param{object_id} );

	$variable{uri} = $param{uri};
	ssi::save_params( $variable{uri}, 
			( map { 'log_created_on_start_'.$_ } ( 'year','month','day','hour','minute' ) ),
			( map { 'log_created_on_end_'.$_ } ( 'year','month','day','hour','minute' ) ),
			( 'log_action_id', 'log_limit' ),
			);
	
} # end sub _logs_contents

# .json
sub _specifications {
    my $Object_Type;
	if ( $param{object_type_id} ) {
		$Object_Type = openprint::Object_Type->find_one( id=>$param{object_type_id} );
	} elsif ( $param{object_type} ) {
		$Object_Type = openprint::Object_Type->find_one( name=>$param{object_type} );
	} elsif ( $param{spec_id} ) {
		my $Spec = new openprint::Object_Specification($param{spec_id});
		my $Object = $Spec->Object();
		$Object_Type = $Object->Object_Type();
	}
    if ( ! $Object_Type ) {
        $log->error('Object type not found : ' . $param{object_type} );
        $variable{error} .= 'Unable to load specifications. Please try again later';
        return;
    } # end if
    my $Object = $variable{Object} = $Object_Type->Object( $param{object_id} );

    foreach my $Spec ( $Object->Specifications() ) {
        if (
                ( exists $param{'spec_name-'.$$Spec{id}} )
                and ( ( $param{'spec_name-'.$$Spec{id}} ne $$Spec{name} ) or ( $param{'spec_value-'.$$Spec{id}} ne $$Spec{value} ) )
           ) {
            $variable{error} .= $Spec->save({ name=>$param{'spec_name-'.$$Spec{id}}, value=>$param{'spec_value-'.$$Spec{id}}});
        } # end if
    } # end foreach spec

	if ( $param{func} eq 'Add' ) {
		my $Spec = $variable{Spec} = new openprint::Object_Specification();
		$variable{error} .= $Spec->save({Object=>$Object, name=>$param{name}, value=>$param{value}});
	} elsif ( $param{func} eq 'Del' ) {
		my $Spec = $variable{Spec} = new openprint::Object_Specification($param{spec_id});
		$variable{error} .= $Spec->delete();
	} # end if


} # end sub _specifications
sub _specification {
	my $Spec = $variable{Spec} = new openprint::Object_Specification($param{spec_id});
} # end sub _specification

sub _location_ddm {
}
1;
__END__
