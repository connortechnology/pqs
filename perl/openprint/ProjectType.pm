use strict;
package openprint::ProjectType;
our @ISA = qw(openprint::Object);

require openprint::Object;
require openprint::Log;
#require openprint::ProjectType_Template;
require openprint;
require openprint::ProjectTypeCategory;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'tbl_projecttypes';
$serial = 'project_types_id_seq';

%fields = (
	id		    	=>	'lngindex',
	name		  	=>	'strid',
	description	=>	'strname',
  category_id	=>	'lnggroup',
	url		    	=>	'strurl',
	sorting	  	=>	'lngsort',
  #type			  =>	'type',
  #please_call	=>	'please_call',
	category		=>	undef,
  #deleted	  	=> 'deleted',
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	name  	=>	[ 's/\s//g' ],
);
%defaults = (
	id			    =>	undef,
	category_id	=>	undef,
	sorting	  	=>	undef,
	please_call	=>	0,
	deleted   	=>	0,
);

sub save {
	my ( $self, $params ) = @_;
	if ( ( my $error = $self->SUPER::save( $params ) ) ) {
		return $error;
	} else {
		# self->required_services is guaranteed to populate $$self{required_services}
		$self->required_services( $$params{required_services} );
		sql::execute( undef, undef, q{DELETE FROM ProjectType_RequiredServices WHERE ProjectType_id=?}, $$self{id} );
		# The union gets rid of duplicates
		foreach my $servicetype_id ( sets::union( @{$$self{required_services}} ) ) {
			next if ! $servicetype_id;
			sql::insert( undef, undef, 'ProjectType_RequiredServices', ['ProjectType_id', $$self{id}, 'ServiceType_id', $servicetype_id ] );
		} # end foreach
		$self->blocked_services( $$params{blocked_services} );
		sql::execute( undef, undef, q{DELETE FROM ProjectType_BlockedServices WHERE projecttype_id=?}, $$self{id} );
		# The union gets rid of duplicates
		foreach my $servicetype_id ( sets::union( @{$$self{blocked_services}} ) ) {
			sql::insert( undef, undef, 'ProjectType_BlockedServices', ['projecttype_id', $$self{id}, 'servicetype_id', $servicetype_id ] );
		} # end foreach
	} # end if
	return '';
} # end sub save

sub next {
	my $self = shift;

  my $next_id;
	if ( $$self{name} ) {
		($next_id) = sql::execute( undef, undef, q{SELECT id FROM Project_Types WHERE name = (SELECT MIN(name) FROM Project_Types WHERE name>?)}, $$self{name} );
		if ( ! $next_id ) {
			( $next_id ) = sql::execute( undef, undef, q{SELECT id FROM Project_Types WHERE name = (SELECT MAX(name) FROM Project_Types WHERE name<?)}, $$self{name} );
		} # end if
	} # end if
	( $next_id ) = sql::execute( undef, undef, q{SELECT MIN(id) FROM Project_Types} ) if ! $next_id;
	return new openprint::ProjectType( $next_id );
} # end sub next

sub prev {
	my $self = shift;
	if ( $$self{name} ) {
		($_) = sql::execute( undef, undef, q{SELECT Id FROM Project_Types WHERE name = (SELECT MAX(name) FROM Project_Types WHERE name<?)}, $$self{name} );
		if ( ! $_ ) {
			( $_ ) = sql::execute( undef, undef, q{SELECT Id FROM Project_Types WHERE name = (SELECT MIN(name) FROM Project_Types WHERE name>?)}, $$self{name} );
		} # end if
	} # end if name
	( $_ ) = sql::execute( undef, undef, q{SELECT MIN(id) FROM Project_Types} ) if ! $_;
	return new openprint::ProjectType( $_ );
} # end sub prev

sub required_services {
	my $self = shift;
	if ( @_ > 1 ) {
		@{$$self{required_services}} = @_;
	} elsif ( @_ ) {
		if ( ref $_[0] eq 'ARRAY' ) {
			$$self{required_services} = $_[0];
		} elsif ( $_[0] ) {
			$$self{required_services} = [$_[0]];
		} # end if
	} # end if
	if ( ! $$self{required_services} ) {
		if ( $$self{id} ) {
			@{$$self{required_services}} = sql::execute( undef, undef, q{SELECT ServiceType_id FROM ProjectType_RequiredServices WHERE ProjectType_id=?}, $$self{id} );
		} else {
			@{$$self{required_services}} = ();
		} # end if
	} # end if
	return @{$$self{required_services}};
} # end sub required_services

sub required_ServiceTypes {
	my @servicetype_ids = $_[0]->required_services();
	return openprint::ServiceType->find( id=> \@servicetype_ids ) if @servicetype_ids;
	return ();
} # end sub require_ServiceTypes

sub blocked_services {
	my $self = shift;
	if ( @_ > 1 ) {
		@{$$self{blocked_services}} = @_;
	} elsif ( @_ ) {
		if ( ref $_[0] eq 'ARRAY' ) {
			$$self{blocked_services} = $_[0];
		} elsif ( $_[0] ) {
			$$self{blocked_services} = [$_[0]];
		} # end if
	} # end if
	if ( ! $$self{blocked_services} ) {
		if ( $$self{id} ) {
			@{$$self{blocked_services}} = sql::execute( undef, undef, q{SELECT ServiceType_id FROM ProjectType_BlockedServices WHERE ProjectType_id=?}, $$self{id} );
		} else {
			@{$$self{blocked_services}} = ();
		} # end if
	} # end if
	return @{$$self{blocked_services}};
} # end sub blocked_services

sub blocked_ServiceTypes {
	return openprint::ServiceType->find( id=>[ $_[0]->blocked_services() ] ) if $_[0]->blocked_services();
	return ();
} # end sub blocked_ServiceTypes

sub destroy {
	my $self = shift;

	my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( undef, undef, q{DELETE FROM projecttype_defaults WHERE projecttype_id=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM ProjectTemplate WHERE projecttype_id=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM Paper_Recommendations WHERE lngProjectTypeIndex=?}, $$self{id} );
	sql::execute( undef, undef, q{DELETE FROM ProjectType_RequiredServices WHERE ProjectType_Id=?}, $$self{id} );
	sql::update( undef, undef, 'Projects', ['type_id=?',$$self{id}], 'type_id', undef );
	sql::execute( undef, undef, q{DELETE FROM Project_Types WHERE Id=?}, $$self{id} );
	sql::end_transaction( $openprint::dbh, $ac );

	(new openprint::Log())->save({ action=>'Delete Project Type', note=>"Project Type ID: $$self{id} Project Type: $$self{name}"});
	return;
} # end sub destroy

sub Templates {
	my ( $self, %params ) = @_;
	$params{projecttype_id} = $$self{id};
	return openprint::ProjectType_Template->find(%params);
} # end sub Templates

sub category {
	if ( @_ > 1 ) {
		$_[0]{category} = $_[1];
		if ( defined $_[1] ) {
			my $Category = openprint::ProjectTypeCategory->find_one( 'name lc' => lc $_[1] );
			if ( ! $Category ) {
				$Category = new openprint::ProjectTypeCategory();
				$Category->save({name=>$_[1]});
			}
			$_[0]{Category} = $Category;
			$_[0]{category_id} = $$Category{id};
		} else {
			delete $_[0]{Category};
			undef $$_[0]{category_id};
		}
	}

	if ( ! exists $_[0]{category} ) {
		if ( ( ! exists $_[0]{Category} ) and $_[0]{category_id} ) {
			$_[0]{Category} = new openprint::ProjectTypeCategory( $_[0]{category_id} );
		}
		if ( $_[0]{Category} ) {
			$_[0]{category} = $_[0]{Category}->name();
		}
	}
	return $_[0]{category};
} # end sub category

1;
__END__
