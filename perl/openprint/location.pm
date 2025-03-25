use strict;
package openprint::location;

require openprint::Location;
use openprint ();
use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub _load_location {
} # end sub _load_location

sub _locations {
} # end sub _locations

sub list {
} # end sub list

sub _action {
} # end sub _action

sub edit {
	$param{location_id} = openprint::Location->transform( id => $param{location_id} );
	my $Location = $variable{Location} = new openprint::Location( $param{location_id} );
	if ( $param{action} eq 'Save' ) {
		foreach ( 'country','state','city','location' ) {
			$param{$_} = openprint::Location->transform( name=>$param{$_} );
		}	
		my $parent_id;
		if ( $param{country} ) {
			my $Country = openprint::Location->find_one('name lc'=> lc $param{country}, type=>'country' );
			if ( ! $Country ) {
				$Country = new openprint::Location();
				$variable{error} .= $Country->save({name=>$param{country}, type=>'country'});
			} # end if
			$parent_id = $param{country_id} = $Country->id();
		} # end if
		if ( $param{country_id} ) {
			my $Country = new openprint::Location($param{country_id});
			if ( $Country->id() ) {
				$parent_id = $param{country_id};
			} else {
				$log->error('Country specified, but not found!?');
			} # end if
		} # end if

		if ( $param{state} ) {
			my $State = openprint::Location->find_one('name lc'=> lc $param{state}, type=>['state','province']);
			if ( ! $State ) {
				$State = new openprint::Location();
				$variable{error} .= $State->save({name=>$param{state}, type=>'state', parent_id=>$param{country_id}});
			} # end if
			$param{state_id} = $State->id();
		} # end if
		if ( $param{state_id} ) {
			my $State = new openprint::Location($param{state_id});
			if ( $State->id() ) {
				if ( $parent_id and ! $State->parent_id() ) {
					$State->save({parent_id=>$parent_id});
				} # end if
				$parent_id = $param{state_id};
			} else {
				$log->error('State specified, but not found!?');
			} # end if
		} # end if
		if ( $param{city} ) {
			my $City = openprint::Location->find_one('name lc'=> lc $param{city}, type=>'city');
			if ( ! $City ) {
				$City = new openprint::Location();
				$variable{error} .= $City->save({name=>$param{city}, type=>'city', parent_id=>$param{state_id}});
			} # end if
			$param{city_id} = $City->id();
		} # end if
		if ( $param{city_id} ) {
			my $City = new openprint::Location($param{city_id});
			if ( $City->id() ) {
				if ( $parent_id and ! $City->parent_id() ) {
					$City->save({parent_id=>$parent_id});
				} # end if
				$parent_id = $param{city_id};
			} else {
				$log->error('City specified, but not found!?');
			} # end if
		} # end if

		my $Type = new openprint::Location_Type($param{location_type_id});
			
		if ( ( $_ = openprint::Location->find_one(
			( $param{location_id} ? ( 'id !='=>$param{location_id} ) : () ),
			'name lc'=> lc $param{location}, 
			( ( $$Type{name} eq 'city' and $param{state_id} ) ? ( parent_id=>$param{state_id} ) : () ),
			( ( $$Type{name} eq 'state' and $param{country_id} ) ? ( parent_id=>$param{country_id} ) : () ),
			( ( $$Type{name} eq 'province' and $param{country_id} ) ? ( parent_id=>$param{country_id} ) : () ),
			( $param{location_type_id} ? ( type_id=>$param{location_type_id} ) : () ),
			) ) ) {
			$variable{error} .= 'A location with that name at that place already exists.';
		} else {
			if ( $param{url} ) {
				if ( ! ( $param{url} =~ /^https?:\/\//i ) ) {
					$param{url} = 'http://'.$param{url};
				} # end if
			} # end if
			$variable{error} .= $Location->save({
          (exists $param{short} ? (short=>$param{short}) : ()),
					name		=>	$param{location}, 
					description	=>	$param{description},
					parent_id	=>	$parent_id, 
					company_id	=>	$param{company_id},
					address		=>	$param{address},
					postalcode	=>	$param{postalcode},
					url			=>	$param{url},
					latitude	=>	$param{latitude},
					longitude	=>	$param{longitude},
					( $param{location_type_id} ? ( type_id => $param{location_type_id} ) : ( type	=>	'place' ) ),
					});
			(new openprint::Log())->save({ action=>($param{location_id} ? 'Update Location' : 'Create Location'), object=>'Location', object_id=>$Location->id()});
		} # end if
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/location/view.html?location_id='.$Location->id();
		} # end if
	} elsif ( $param{action} eq 'Delete' ) {
		$variable{error} .= $Location->delete();
	} elsif ( $param{action} eq 'Destroy' ) {
		$variable{error} .= $Location->destroy();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/location/list.html';
			$variable{information} = 'Location destroyed.';
		} # end if
	} elsif ( $param{action} eq 'Undelete' ) {
		$variable{error} .= $Location->undelete();
	} # end if
} # end sub edit

sub view {
	$param{location_id} = openprint::Location->transform('id', $param{location_id});
	my $Location = $variable{Location} = new openprint::Location( $param{location_id} );
	if ( $param{action} eq 'Delete' ) {
		$variable{error} .= $Location->delete();
	} elsif ( $param{action} eq 'Destroy' ) {
		$variable{error} .= $Location->destroy();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/location/list.html';
			$variable{information} = 'Location destroyed.';
		} # end if
	} elsif ( $param{action} eq 'Undelete' ) {
		$variable{error} .= $Location->undelete();
	} elsif ( $param{filename} ) {
		my $Album = $Location->Album();
		if ( ! $Album->id() ) {
			$variable{error} .= $Album->save({name=>'Photos for ' . $Location->name()});
			$variable{error} .= $Location->save({album_id=>$Album->id()});
		} # end if
		$variable{error} = $Album->upload( 'filename' );
		if ( ! $variable{error} ) {
			$variable{information} .= "File $param{filename} was uploaded successfully.<br/>";
		} # end if
	} # end if
} # end sub view

sub _photos {
	my $Location = $variable{Location} = new openprint::Location( $param{location_id} );
	if ( $param{action} eq 'delete' ) {
		my $Photo = openprint::Photo_in_Album->find_one( {album_id=>$$Location{album_id}, asset_id=>$param{asset_id} } );
		$variable{error} .= $Photo->delete() if $Photo->id();
	} # end if
} # end sub _photos

sub search {
	_search();
	if ( ! exists $session{'/location/search.html?type_id'} ) {
		if ( $_ = openprint::Location_Type->find_one(name=>'place') ) {
			$session{'/location/search.html?type_id'} = $_->id();
		} # end if
	} # end if

	my $Location = new openprint::User( $session{user_id} )->Location() if $session{user_id};;
	if ( ! ( $Location and $Location->id() ) ) {
		$Location = openprint::Location::from_ip();
	} # end if
	if ( $Location and $Location->id() ) {
		my $Country = $Location->ancestor(type=>'country');
		my $State = $Location->ancestor(type=>'state');
		$session{'/location/search.html?state_id'} = $State->id() if $State and ! exists $session{'/location/search.html?state_id'};
		$session{'/location/search.html?country_id'} = $Country->id() if $Country and ! exists $session{'/location/search.html?country_id'};
	} # end if
} # end sub search

sub _search {
	if ( ! $param{btnFunction} ) {
		ssi::save_params( '/location/search.html', ( 
				#'starting_on_start_year','starting_on_start_month','starting_on_start_day',
				#'starting_on_end_year','starting_on_end_month','starting_on_end_day',
				'type_id', 'user_id', 'category_id', 'country_id', 'state_id', 'city_id',
				'company_id', ) );
	} # end if
	#$session{'/location/search.html?type_id'} = openprint::Location_Type->find_one(name=>'place')->id() if ! exists $session{'/location/search.html?type_id'};
} # end sub _search

sub _ddm {
} # end sub _ddm

sub _location_fields {
	$param{location_id} = openprint::Location->transform('id', $param{location_id});
	$variable{Location} = new openprint::Location( $param{location_id} );
} # end sub _location_fields
1;
__END__
