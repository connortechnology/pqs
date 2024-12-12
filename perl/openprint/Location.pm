use strict;
require openprint;
require openprint::Location_Type;
require Math::Round;
#use Geo::IP;

my $geo;
package openprint::Location;
our @ISA = qw( openprint::Object );

use constant PI => atan2(1,1)*4;
# 3.14159265358979;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults $default_sort $cache_field $cached );
$debug = 0;
$cached = 0;
$cache_field='short';
$default_sort = 'lower(name)';
$table = 'locations';
$serial = 'locations_id_seq';
%fields = (
	id			=>	'id',
	name		=>	'name',
	description	=>	'description',
	short		=>	'short',
	parent_id	=>	'parent_id',
	coordinates	=>	'coordinates',
	updated_on	=>	'updated_on',
	created_on	=>	'created_on',
	# type refers to state/country/postalcode, etc... to help search the location db in other ways
	type_id		=>	'type_id',
	type		=>	undef,
	created_by	=>	'created_by',
	company_id	=>	'company_id',
	postalcode	=>	'postalcode',
	address		=>	'address',
	latitude	=>	'latitude',
	longitude	=>	'longitude',
	url			=>	'url',	
	asset_id	=>	'asset_id',
	album_id	=>	'album_id',
	deleted		=>	'deleted',
);
%find_fields = (
	type		=>	'(SELECT name FROM Location_Types WHERE location_types.id = locations.type_id)',
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	parent_id	=>	[ 's/\D//g', '<2147483647' ],
	postalcode	=>	[ 'tr/[a-z]/[A-Z]/' ],
    name		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    address		=>	[ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    postalcode	=>	[ 's/\s*//' ],
	latitude	=>	[ 's/[^\-\d\.]//g' ],
	longitude	=>	[ 's/[^\-\d\.]//g' ],
);
%defaults = (
	company_id	=>	undef,
	created_by	=>	q`$session{user_id}`,
	created_on	=>	q`'NOW()'`,
	updated_on	=>	q`'NOW()'`,
	parent_id		=>	undef,
	type_id		=>	undef,
	latitude		=>	undef,
	longitude		=>	undef,
	asset_id		=>	undef,
	album_id		=>	undef,
	deleted		=>	'0',
	name			=>	undef,
);

sub children {
	return openprint::Location->find( parent_id => $_[0]{id} ) if $_[0]{id};
	return ();
} # end sub children

sub get_all_children {
	my @results;
	
	foreach my $child ( $_[0]->children() ) {
		# Prevent infinite loop
		next if $$child{id} and sets::isin( $$child{id}, [ map { $_->id() } @results ] );
		push @results, $child, $child->get_all_children();
	} # end foreach child
	return @results;
} # end sub get_all_children

sub parent {
  $openprint::log->error("use of deprecated method Location parent");
	return new openprint::Location( $_[0]{parent_id}) if $_[0]{parent_id};
} # end sub parent

sub Parent {
	# _map has code that does while ( $_->Parent() = ) 
	return new openprint::Location( $_[0]{parent_id}) if $_[0]{parent_id};
	return;
} # end sub parent

sub Root {
	my $P = shift;
	
	my $continue = 0;

	while ( $P->parent_id() ) {
		my $P2 = $P->Parent();
		if ( @_ ) {
			my $thing = $_[0];
			if ( $P2->$thing() eq $_[1] ) {
				$continue = 1;
			} elsif ( $continue ) {
				last;
			}
		}
		$P = $P2;
	} # end while 
	return $P;
} # end sub Root

sub Parents {
	if ( ( ! $_[0]{id} ) or ! $_[0]{parent_id} ) {
		return ();
	} 
	if ( ! $_[0]{Parents} ) {
		$_[0]{Parents} = [ $_[0]->Parent(), $_[0]->Parent()->Parents() ];
	}
	return @{$_[0]{Parents}};
} # end sub Parents

sub Type {
	return new openprint::Location_Type( $_[0]{type_id} );
} # end sub Type

sub type {
	if ( @_ > 1 ) {
		my $Type;
		if ( $_[1] ) {
			$Type = openprint::Location_Type->find_one('name lc'=>lc openprint::Location_Type->transform('name',$_[1]));
			if ( ! $Type ) {
				$Type = new openprint::Location_Type();
				$Type->save({'name'=>$_[1]});
			} # end if
		} else {
			$Type = new openprint::Location_Type();
		} 
#$openprint::log->debug("Type: " . $Type->to_string() );
		$_[0]{type_id} = $Type->id();
		$_[0]{type} = $Type->name();
	} elsif ( ( ! defined $_[0]{type} ) and $_[0]{type_id} ) {
		$_[0]{type} = $_[0]->Type()->name();
	} # end if
#$openprint::log->debug("Location::type " . $_[0]->to_string() );
	return $_[0]{type};
} # end sub type

# find an ancestor that fits some criteria, so if we wanted to find the city that something is located in, we could call this with a tpye of city
# It's recursive of course
sub ancestor {
	my $self = shift;
	return if ! @_;
	my ( $value ) = $self->get( $_[0] );
	if ( $value and sets::isin( $value, $_[1] ) ) {
		#$openprint::log->debug( "Returning Location: $_[0] ($$self{name}) ($value) != $_[1]");
		return $self;
	#} else {
		#$openprint::log->debug( "nA Location: $_[0] ($$self{name}) ($value) != $_[1]");
	} # end if
	if ( $$self{parent_id} ) {
#$openprint::log->debug("Recursing" );
		return $self->Parent()->ancestor( @_ );
	} # end if
	return;
} # end sub ancestor

# Figures out a given type's parent type should be, so city->state, etc.
sub parent_type {
	my $type;
	if ( $_[0] eq 'openprint::Location' ) {
		$type = $_[1];
	} else { 
		$type = $_[0]->type();
	} # end if
	if ( $type eq 'country' ) {
		return;
	} elsif ( $type eq 'state' ) {
		return 'country';
	} elsif ( $type eq 'city' ) {
		return 'state';
	} elsif ( $type eq 'place' ) {
		return 'city';
	} # end if
} # end sub parent_type

sub child_type {
	my $type;
	if ( $_[0] eq 'openprint::Location' ) {
		$type = $_[1];
	} else { 
		$type = $_[0]->type();
	} # end if
	if ( $type eq 'country' ) {
		return 'state';
	} elsif ( $type eq 'state' ) {
		return 'city';
	} elsif ( $type eq 'city' ) {
		return 'place';
	} elsif ( $type eq 'place' ) {
		return;
	} # end if
} # end sub child_type

sub child_types {
	return map { 
	if ( $_ eq 'country' ) {
		( 'state', 'province' );
	} elsif ( $_ eq 'state' ) {
		( 'city' );
	} elsif ( $_ eq 'city' ) {
		( 'place' );
	} else {
		( );
	} # end if
	} @_;
}

sub latitude {
	if ( @_ > 1 ) {
		$_[0]{latitude} = $_[1];
	} # end if
	return $_[0]{latitude};
}
sub longitude {
	if ( @_ > 1 ) {
		$_[0]{longitude} = $_[1];
	} # end if
	return $_[0]{longitude};
}

# Does a google lookup on some string and returns a Location object based on what it returns
sub google {
	require Geo::Coder::Googlev3;
	my $string = $_[0];
	$string .= ' ' . $_[1] if @_ > 1;
	$string =~ s/ /+/g;
	if ( ! $string ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->debug("No location to search google for from $caller:$line");
		return;
	}
	my $coder = Geo::Coder::Googlev3->new();
	my $location;
	eval {
		$location = $coder->geocode( location => $string );
	};
	if ( ! $location ) {
		$openprint::log->debug("No location for $string");
		return;
	} # endif 
	$openprint::log->warn("No placemrk" . Data::Dumper::Dumper( $location ) );

	my ( $latitude, $longitude, $country, $postalcode, $address, $state, $city, $number, $street );

	if ( $$location{Point} ) {
		my $Point = $$location{Point};
		my $coordinates = $$Point{coordinates};
		$latitude = openprint::Location->transform('latitude', @{$coordinates}[0] );
		$longitude = openprint::Location->transform('longitude', @{$coordinates}[1] );
	} elsif ( $$location{geometry} ) {
		if ( $$location{geometry}{location} ) {
			$latitude = openprint::Location->transform('latitude',  $$location{geometry}{location}{lat} );
			$longitude = openprint::Location->transform('longitude',  $$location{geometry}{location}{lng} );
		} # end if
	} # end if
	if ( ! ( $latitude and $longitude ) ) {
		return;
	} # end if

	if ( $$location{address_components} ) {
		foreach my $component ( @{$$location{address_components}} ) {
			if ( sets::isin( 'locality', $$component{types} ) ) {
				$city = $$component{longname};
			} elsif ( sets::isin( 'administrative_area_level_1', $$component{types} ) ) {
				$state = $$component{longname};
			} elsif ( sets::isin( 'country', $$component{types} ) ) {
				$country = $$component{longname};
			} elsif ( sets::isin( 'postal_code', $$component{types} ) ) {
				$postalcode = $$component{longname};
			} elsif ( sets::isin( 'street_number', $$component{types} ) ) {
				$number = $$component{longname};
			} elsif ( sets::isin( 'route', $$component{types} ) ) {
				$street = $$component{longname};
			} # end if
		} # end foreach component
	} # end if

	$address = $number . ' ' . $street if $number and $street;

	if ( $$location{AddressDetails} ) {
		my $Address = $$location{AddressDetails};
		if ( $$Address{Country} ) {
			my $Country = $$Address{Country};
			if ( $$Country{AdministrativeArea} ) {
				my $AdministrativeArea = $$Country{AdministrativeArea};
				if ( $$AdministrativeArea{SubAdministrativeArea} ) {
					$openprint::log->debug('Have Sub AdministrativeArea');
					$AdministrativeArea = $$AdministrativeArea{SubAdministrativeArea};
					$openprint::log->debug(Data::Dumper::Dumper($AdministrativeArea));
				} # end if

				if ( $$AdministrativeArea{Locality} ) {
					my $Locality = $$AdministrativeArea{Locality};
					if ( $$Locality{PostalCode} ) {
						$openprint::log->debug("Have Postal code" . $$Locality{PostalCode}{PostalCodeNumber});
						$postalcode = $$Locality{PostalCode}{PostalCodeNumber};
					} else {
						$openprint::log->debug("No PostalCode");
					} # en dif
				} else {
					$openprint::log->debug("No Locality");
				} # end if
			} else {
				$openprint::log->debug("No Administrative Area");
			} # end if
		} else {
			$openprint::log->debug("No Coutry");
		} # end if
	} # end if has AddressDetails

	my $parent;
	if ( $city ) {
		$parent = $city;
	} elsif ( $state ) {
		$parent = $state;
	} elsif ( $country ) {
		$parent = $country;
	} # end if
	
	my $Location = new openprint::Location();
	$Location->save({
		name		=>	$_[0],
		parent		=>	$parent,
		latitude	=>	$latitude,
		longitude	=>	$longitude,
		postalcode	=>	$postalcode,
		address		=>	$address,
		});

	return $Location;
} # end sub google

sub get_latitude_and_longitude {
	require Geo::Coder::Googlev3;
	my $coder = Geo::Coder::Googlev3->new();
	my $string = join(',',$_[0]->name(),$_[0]->address(), $_[0]->postalcode(), map{$_->name()}$_[0]->Parents()) if $_[0]->address();
	$string =~ s/ /+/g;
	$openprint::log->debug('Get: ' . $string );
	return 0 if ! $string;
	my $location = $coder->geocode( location => $string );
	if ( ! $location ) {
		$openprint::log->error("No location for $string");
		return;
	} # enmdif 
	$openprint::log->warn("No placemrk" . Data::Dumper::Dumper( $location ) );

	my $use = 0;
	if ( $$location{Point} ) {
		my $Point = $$location{Point};
		my $coordinates = $$Point{coordinates};
		$_[0]{latitude} = openprint::Location->transform('latitude', @{$coordinates}[0] );
		$_[0]{longitude} = openprint::Location->transform('longitude', @{$coordinates}[1] );
		return 1;
	} elsif ( $$location{geometry} ) {
		if ( $$location{geometry}{location} ) {
			$_[0]{latitude} = openprint::Location->transform('latitude',  $$location{geometry}{location}{lat} );
			$_[0]{longitude} = openprint::Location->transform('longitude',  $$location{geometry}{location}{lng} );
			return 1;
		} # end if
	} else {
		my $Address = $$location{AddressDetails};
		if ( $$Address{Country} ) {
			my $Country = $$Address{Country};
			if ( $$Country{AdministrativeArea} ) {
				my $AdministrativeArea = $$Country{AdministrativeArea};
				if ( $$AdministrativeArea{SubAdministrativeArea} ) {
					$openprint::log->debug('Have Sub AdministrativeArea');
					$AdministrativeArea = $$AdministrativeArea{SubAdministrativeArea};
					$openprint::log->debug(Data::Dumper::Dumper($AdministrativeArea));
				} # end if

				if ( $$AdministrativeArea{Locality} ) {
					my $Locality = $$AdministrativeArea{Locality};
					if ( $_[0]{postalcode} ) {
						if ( $$Locality{PostalCode} ) {
							$openprint::log->debug("Have Postal code" . $$Locality{PostalCode}{PostalCodeNumber});

							if ( $$Locality{PostalCode}{PostalCodeNumber} eq $_[0]{postalcode} ) {
								$use = 1;
							} # end if
						} else {
							$openprint::log->debug("No PostalCode");
						} # en dif
					} # en dif postalcode
				} else {
					$openprint::log->debug("No Locality");
				} # end if
			} else {
				$openprint::log->debug("No Administrative Area");
			} # end if
		} else {
			$openprint::log->debug("No Coutry");
		} # end if

		if ( $use ) {
			my $Point = $$location{Point};
			my $coordinates = $$Point{coordinates};
			$_[0]{latitude} = openprint::Location->transform('latitude', @{$coordinates}[0] );
			$_[0]{longitude} = openprint::Location->transform('longitude', @{$coordinates}[1] );
	$openprint::log->debug("Resulting coords: $_[0]{latitude}, $_[0]{longitude}");
			$_[0]->save();
			return 1;
		} # end if
	} # end if
	return 0;
} # end sub get_latitude_longitude

sub distance {
	shift @_ if $_[0] eq 'openprint::Location';
	shift @_ if ref $_[0] eq 'openprint::Location';

	my ($lat1, $lon1, $lat2, $lon2, $unit) = @_;
	my $theta = $lon1 - $lon2;
	my $dist = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
	$dist  = acos($dist);
	$dist = rad2deg($dist);
	$dist = $dist * 60 * 1.1515;
  $openprint::log->debug("Calcing distance from $lat1,$lon1 to $lat2,$lon2 units: $unit, dist: $dist");
	if ($unit eq "K") {
		$dist = $dist * 1.609344;
	} elsif ($unit eq "N") {
		$dist = $dist * 0.8684;
	}
	return Math::Round::nearest(0.1,$dist);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function get the arccos function using arctan function   :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub acos {
	return atan2(sqrt(1 - $_[0]**2), $_[0]);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts decimal degrees to radians             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub deg2rad {
	return ($_[0] * PI / 180);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts radians to decimal degrees             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub rad2deg {
	return ($_[0] * 180 / PI);
}

sub thumbnail_id {
	if ( ! exists $_[0]{thumbnail_id} ) {
        my $Album = $_[0]->Album();
        if ( $$Album{thumbnail_id} ) {
			$_[0]{thumbnail_id} = $$Album{thumbnail_id};
        } elsif ( $$Album{id} and my @Photos = $Album->Photos() ) {
            $_[0]{thumbnail_id} = $Photos[0]->asset_id();
        } # end if
	} # end if
	return $_[0]{thumbnail_id};
} # end sub thumbnail_id

sub Asset {
require openprint::Asset;
    if ( ! $_[0]{Asset} ) {
		$_[0]{Asset} = new openprint::Asset( $_[0]->thumbnail_id() );
    } # end if
    return $_[0]{Asset};
} # end sub Asset

sub Photos {
	if ( ! $_[0]{album_id} ) {
		return ();
	} # end if
	return $_[0]->Album()->Photos( );
} # end sub Photos

sub Album {
require openprint::Photo_Album;
	return new openprint::Photo_Album( $_[0]{album_id} );
} # end sub Album

sub can_edit {
	if ( ! $_[0]{id} ) {
		return 0;
	} # end if
	if ( ! $openprint::session{user_id} ) {
		return 0;
	} # end if
	if ( $openprint::session{user_id} == $_[0]{created_by} or $openprint::session{user_type} eq 'A' ) {
		return 1;
	} # end if
	if ( $_[0]{company_id} ) {
		my $Company = $_[0]->Company();
		if ( $Company->can_edit() ) {
			return 1;
		}
	}
	return 0;
} # end sub can_edit

sub address_line {
	if ( ! $_[0]{address_line} ) {
		my $L = $_[0];
		$_[0]{address_line} = '';
		if ( $L->address() ) {
			$_[0]{address_line} .= $L->address() . ', ';
		} # end if
		$_[0]{address_line} .= join(', ', map { $_->name() } $L->Parents() );
		if ( $L->postalcode() ) {
			$_[0]{address_line} .= ', '.$L->postalcode();
		} # end if
	} # end if
	return $_[0]{address_line};
} # end sub address_line

sub address_formatted {
	if ( ! $_[0]{address_formatted} ) {
		my $L = $_[0];
		$_[0]{address_formatted} = '';
		if ( $$L{company_id} ) {
			$$L{address_formatted} .= $L->Company()->name()."\n";
		}
		if ( $L->address() ) {
			$_[0]{address_formatted} .= $L->address() . "\n";
		} # end if
		$_[0]{address_formatted} .= join(', ', map { $_->name() } $L->Parents() ) . "\n";
		if ( $L->postalcode() ) {
			$_[0]{address_formatted} .= $L->postalcode() . "\n";
		} # end if
	} # end if
	return $_[0]{address_formatted};
}

sub where {
	if ( ! $_[0]{where} ) {
		my $L = $_[0];
		$_[0]{where} .= join(', ', map { $_->name() } $L->Parents() );
		if ( $L->address() or $L->postalcode() ) {
			$_[0]{where} .= '<br/>' . $L->address() . ', '.$L->postalcode();
		} # end if
	} # end if
	return $_[0]{where};
} # end sub where

sub address {
	if ( @_ > 1 ) {
		$_[0]{address} = $_[1];
	} # end if
	if ( ! $_[0]{address} ) {
		if ( $_[0]{parent_id} ) {
			$_[0]{address} = $_[0]->Parent()->address();
		} # end if
	} # end if
	return $_[0]{address};
} # end sub address

sub postalcode {
	if ( @_ > 1 ) {
		$_[0]{postalcode} = $_[1];
	} # end if
	if ( ! $_[0]{postalcode} ) {
		if ( $_[0]{parent_id} ) {
			$_[0]{postalcode} = $_[0]->Parent()->postalcode();
		} # end if
	} # end if
	return $_[0]{postalcode};
} #  end sub postalcode

sub where_link {
	if ( ! $_[0]{where_link} ) {
		my $L = $_[0];
		$_[0]{where_link} = '<a href="/location/view.html?location_id='.$L->id().'">';
		if ( $L->address() or $L->postalcode() ) {
			$_[0]{where_link} .= '<br/>' . $L->address() . ', '.$L->postalcode();
		} # end if
		$_[0]{where_link} .= '</a>';
		$_[0]{where_link} .= join(', ', map { $_->link_to() } $L->Parents() );
		if ( $L->url() ) {
			$_[0]{where_link} .= '<br/><a target="_blank" href="'.$L->url().'">'.$L->url().'</a>';
		} # end if
	} # end if
	return $_[0]{where_link};
} # end sub where_link

sub link_to {
	return join('', '<a href="/location/view.html?location_id=', $_[0]{id}, '">', ( @_ > 1 ? $_[1] : $_[0]{name} ), '</a>' );
} # end sub link_to

# Takes a hash, probably %param, and does all the saving neccessary, returns a Location object.
# If no location name is given, returns the parent. So if in an event I specified Toronto, then the location would be Toronto
sub save_location {
	my $param = $_[0];
	my $parent_id;
	my $error;

	if ( $$param{country} ) {
		my $Country = openprint::Location->find_one('name lc'=> lc $$param{country}, type=>'country' );
		if ( ! $Country ) {
			$Country = new openprint::Location();
			$error .= $Country->save({'name'=>$$param{country}, 'type'=>'country'});
		} # end if
		$parent_id = $$param{country_id} = $Country->id();
	} elsif ( $$param{country_id} ) {
		$parent_id = $$param{country_id};
	} # end if
	if ( $$param{state} ) {
		my $State = openprint::Location->find_one('name lc'=> lc $$param{state}, 'type'=>['state','province']);
		if ( ! $State ) {
			$State = new openprint::Location();
			$error .= $State->save({'name'=>$$param{state}, 'type'=>'state', 'parent_id'=>$$param{country_id}});
		} # end if
		$parent_id = $$param{state_id} = $State->id();
	} elsif ( $$param{state_id} ) {
		$parent_id = $$param{state_id};
	} # end if
	if ( $$param{city} ) {
		my $City = openprint::Location->find_one('name lc'=> lc $$param{city}, 'type'=>'city');
		if ( ! $City ) {
			$City = new openprint::Location();
			$error .= $City->save({'name'=>$$param{city}, 'type'=>'city', 'parent_id'=>$$param{state_id}});
		} # end if
		$parent_id = $$param{city_id} = $City->id();
	} elsif ( $$param{city_id} ) {
		$parent_id = $$param{city_id};
	} # end if
	my $Location;
	$$Location = $$param{company_id} if $$param{company_id};

	if ( $$param{location} ) {
		$Location = openprint::Location->find_one('name lc'=> lc openprint::Location->transform(name=>$$param{location}),
			( $$param{address} ? ( 'address lc'=>lc openprint::Location->transform('address',$$param{address}) ) : () ),
			( $parent_id ? ( 'parent_id'=>$parent_id ) : () ),
			);
		if ( ( ! $Location ) and $$param{address} ) {
		$Location = openprint::Location->find_one('name lc'=> lc openprint::Location->transform('name',$$param{location}),
			( $parent_id ? ( 'parent_id'=>$parent_id ) : () ),
			);
		} # end if
		if ( ( ! $Location ) or 
				( $Location->address() and $$param{address} and ( $Location->address() ne openprint::Location->transform('address',$$param{address}) ) ) or
				( $Location->postalcode() and $$param{postalcode} and ( $Location->postalcode() ne openprint::Location->transform('postalcode',$$param{postalcode}) ) ) or
				( $Location->parent_id() != $parent_id )
		   ) {
#$openprint::log->debug("Blah");
#$openprint::log->debug('No location') if ! $Location;
#$openprint::log->debug("Address: $$Location{address} $$param{address} " . openprint::Location->transform('address',$$param{address}) );
#$openprint::log->debug("PostalCode: $$Location{postalcode} $$param{postalcode} " . openprint::Location->transform('postalcode',$$param{postalcode}) );
			# Different from what we have in db, add new
			$Location = new openprint::Location();
			$error .= $Location->save({
					name			=>	$$param{location}, 
					parent_id		=>	$parent_id, 
					($$param{location_type_id}?(type_id=>$$param{location_type_id}):(type => 'place')), 
					address		=>	$$param{address},
					postalcode	=>	$$param{postalcode},
					});
		
		} else {
			my %change;
			$change{address} = $$param{address} if $$param{address} and ! $Location->address();
			$change{postalcode} = $$param{postalcode} if $$param{postalcode} and ! $Location->postalcode();
			if ( %change ) {
$openprint::log->debug("Change:");
				$error .= $Location->save( \%change );
			} # end if
		} # end if
	} elsif ( $$param{location_id} ) {
		$Location = new openprint::Location( $$param{location_id} );
	} elsif ( $parent_id ) {
		$Location = new openprint::Location( $parent_id );
	} # end if
	return $error if $error;
	return $Location;
} # end sub save_location

sub googlemap_html {
	if ( ! exists $_[0]{googlemap_html} ) {
    #my $url = sprintf('http://maps.google.com/maps?f=q&amp;hl=en&amp;ll=%1$s,%2$s&amp;q=%3$s&amp;z=13&amp;output=embed', 
    #$_[0]->latitude(), $_[0]->longitude(), join('+',$_[0]->name(), $_[0]->address(), ( $_[0]->postalcode() ? $_[0]->postalcode() : () ), map{$_->name()} ( $_[0]->Parents() ) ) );

    my $url = sprintf('https://maps.google.com/maps?f=q&amp;hl=en&amp;ll=%1$s,%2$s&amp;z=13&amp;output=embed', 
    $_[0]->latitude(), $_[0]->longitude());
		$url =~ s/ /%20/g;
		$_[0]{googlemap_html} = '<iframe src="'.$url.'" style="width: 100%; height:400px;"></iframe>';
	} # end if
	return $_[0]{googlemap_html};
} # end sub googlemap_html

sub from_ip {
eval {
  require Geo::IPfree;
  if ( ! $geo ) {
    $geo = Geo::IPfree->new();
    #$geo->LoadDB( '/usr/share/GeoIP/GeoIP.dat' );
    #'/usr/share/GeoIP/GeoIP.dat');
    #my $geo = $Geo::IP->open( '/usr/share/GeoIP/GeoIP.dat' );
    $geo->Faster();
  } # end if
};
	my $ip = @_ ? $_[0] : ($ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR});
	if ( ref $geo eq 'Geo::IPfree' ) {
$openprint::log->debug("Doing lookup for $ip");
		my ( $code1, $name1 ) = $geo->LookUp( $ip );
$openprint::log->debug("Back from lookup for $ip");
		my $ac = sql::start_transaction( $openprint::dbh );
		$openprint::dbh->do( 'LOCK TABLE Orders IN SHARE ROW EXCLUSIVE MODE' ) or $openprint::log->error( $openprint::dbi->errstr() );
		my $Country = openprint::Location->find_one('type'=>'country','name lc'=>lc $name1);
		if ( ! $Country ) {
			$Country = new openprint::Location();
			$Country->save({'name'=>$name1,'type'=>'country',short=>$code1});
		} # end if
		sql::end_transaction( $openprint::dbh, $ac );
		return $Country;
	} else {
		$openprint::log->debug("Unknown ref for geo: " . ref $geo);
	} # end if
	if ( ref $geo eq 'Geo::IP' and -e '/usr/share/GeoIP/GeoIPCity.dat' ) {
		my $gi = $geo->LoadDB('/usr/share/GeoIP/GeoIPCity.dat' );
#GeoIPASNum.dat   GeoIPCity.dat    GeoIP.dat        GeoIPv6.dat      GeoLiteCity.dat 
		if ( ! $gi ) {
			$openprint::log->error('No Geo::IP');
			return;
		} # end if

		my $record = $gi->record_by_addr($ip);
		if ( ! $record ) {
			$openprint::log->error("No record for $ip from Geo::IP " . $gi->database_info);

			return;
		} elsif ( $debug ) {
			$openprint::log->error('Got record from Geo::IP' . $gi->database_info);
		} # end if

		my $ac = sql::start_transaction( $openprint::dbh );
		$openprint::dbh->do( 'LOCK TABLE Orders IN SHARE ROW EXCLUSIVE MODE' ) or $openprint::log->error( $openprint::dbi->errstr() );
		my $Country = openprint::Location->find_one('type'=>'country','name lc'=>lc $record->country_name());
		if ( ! $Country ) {
			$Country = new openprint::Location();
			$Country->save({'name'=>$record->country_name(),'type'=>'country'});
		} # end if

		my $State = openprint::Location->find_one('type'=>'state','name lc'=>lc $record->region_name(),'parent_id'=>$Country->id());
		if ( ! $State ) {
			$State = new openprint::Location();
			$State->save({'name'=>$record->region_name(),'type'=>'state','parent_id'=>$Country->id()});
		} # end if
		my $City = openprint::Location->find_one('type'=>'city','name lc'=>lc $record->city(),'parent_id'=>$State->id());

		if ( ! $City ) {
			$City = new openprint::Location();
			$City->save({'name'=>$record->city(),'type'=>'city','parent_id'=>$State->id()});
		} # end if
		sql::end_transaction( $openprint::dbh, $ac );
		return $City;
	} else {
		$openprint::log->error("'/usr/share/GeoIP/GeoIPCity.dat' does not exist.  Perhaps you need to install geoip-database-contrib");
	} # end if
	return;
} # end sub from_ip

sub upload {
	my $self = shift;
	my $Album = $self->Album();
	if ( ! $Album->id() ) {
		$Album->save({ 'Photos for location: ' . $$self{name} });
		$self->save({'album_id'=>$Album->id()});
	} # end if
	return $Album->upload( @_ );
} # end sub upload

sub filters {
	my ( $prefix, $selected, $options ) = @_;

	my $option_string;
	if ( $$options{onSuccess} ) {
		$option_string = 'onSuccess: function(){' . $$options{onSuccess}.'}';
	} # end if
	if ( $option_string ) {
		$option_string = ',{'.$option_string.'}';
	} # end if

	my ( $country_id, $state_id, $city_id );
	if ( ref $selected eq 'openprint::Location' ) {
		$_ = $selected->ancestor('country');
		$country_id = $_->id() if $_;
		$_ = $selected->ancestor('state');
		$state_id = $_->id() if $_;
		$_ = $selected->ancestor('city');
		$city_id = $_->id() if $_;
	} elsif ( ref $selected eq 'HASH' ) {
		( $country_id, $state_id, $city_id ) = @$selected{'country','state','city'};
	} elsif ( ref $selected eq 'ARRAY' ) {
		( $country_id, $state_id, $city_id ) = @$selected;
	} # end if	
$openprint::log->debug("Location::fitlers selected $country_id, $state_id, $city_id");
	my $html = '<li><label>Country</label>';
	my @Countries = openprint::Location->find(type=>'country');
	$html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @Countries ], $country_id, { name=>'country_id', id=>'country_id', onchange=>qq`Location_onchange( this, 'country'$option_string );` } );

	$html .= '</li><li><label>';
	my $Country = new openprint::Location($country_id);
	if ( $Country->name() eq 'Canada' ) {
		$html .= 'Province';
	} elsif ( $Country->name() eq 'United States' ) {
		$html .= 'State';
	} else {
		$html .= 'State/Province';
	} # end if
	$html .= '</label>';
	my @States = openprint::Location->find(type=>[ 'state', 'province'],
			( sets::isin( $country_id, [ map { $_->id() } @Countries ] ) ? ( parent_id=>$country_id ) : () ),
			);
	$html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @States ], $state_id, {
      name=>'state_id', id=>'state_id', onchange=>qq`Location_onchange( this, 'state'$option_string );"` } );

	$html .= '</li><li><label>City</label>';
	my @Cities = openprint::Location->find( order=>'lower(name)', type=>'city',
			( ( $state_id and sets::isin( $state_id, [ map { $_->id() } @States ] )) ? ( parent_id=>$state_id ) : () ),
    );
    $html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @Cities ], $city_id, {
        name=>'city_id', id=>'city_id', onchange=>qq`Location_onchange( this, 'city'$option_string );` } );
	$html .= '</li>';
    #$html .= '<li><label>Place</label>';
    #my @es = openprint::Location->find('order'=>'lower(name)','type'=>'place',
        #( sets::isin( $state_id, [ map { $_->id() } @States ] ) ? ( parent_id=>$state_id ) : () ),
    #);
    #$html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @Cities ], $city_id, { name=>'city_id', id=>'city_id', onchange=>qq`Location_onchange( this, 'city'$option_string );` } );
	#$html .= '</li>';

    return $html;
} # end sub filters

sub html {
	my $self = $_[0];
	my $html = sprintf(q`
			<div class="Location">
				<div class="Assets"><a class="medium %4$s" href="/location/view.html?location_id=%1$d"><img alt="" src="%5$s"/></a></div>
				<div class="Name"><a href="/location/view.html?location_id=%1$d">%2$s</a></div>
				<div class="Where">%3$s</div>
			</div>
			`, $self->id(), ssi::html_escape($self->name()), 
			$self->where(),
			$self->Asset()->layout(),
			$self->Asset()->medium_url(),
			);
	return $html;
} # end  sub html

sub three_letter {
	if ( ! $_[0]{three_letter} ) {
		if ( $_[0]->type() eq 'country' ) {
			if ( $_[0]{name} ) {
				require Locale::Country;
				$_[0]{three_letter} = uc Locale::Country::country2code( $_[0]{name}, 'alpha-3' );
				if ( ! $_[0]{three_letter} ) {
					$openprint::log->warn("No code found for $_[0]{name}");
				}
			}
		} # end if
	} # end if
	return $_[0]{three_letter};
} # end sub three_letter

sub Company {
	return new openprint::Company($_[0]{company_id});
}
1;
__END__
