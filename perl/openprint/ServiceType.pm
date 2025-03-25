use strict;
package openprint::ServiceType;
our @ISA = qw(openprint::Object);
require openprint::Object;
require openprint::ServiceType_Category;
require openprint::ServiceType_Default;

use vars qw( $debug $table $serial %find_fields %fields %transforms %defaults $cache_field $dropdown_field);

$debug = 0;
$table = 'tbl_service_types';
$serial = 'servicetypeindex';
$dropdown_field = 'strdescription';

%fields = (
	id			    	=>	'lngindex',
	name		    	=> 'strid',
	description		=> 'strname',
	url				    => 'strurl',
	type		    	=> 'strtype',
  #category_id		=> 'category_id',
	sorting		  	=> 'lngsort',
	create_visible	=> 'ysncreatevisible',
	view_visible	=> 'ysnviewvisible',
	summary_visible	=> 'summary_visible',
	category		  => undef,
	allow_delete	=> 'allow_delete',
	deleted		  	=> 'deleted',
);
%find_fields = (
	category	=>	'(SELECT name FROM ServiceType_Categories WHERE id=category_id)',
);
%transforms = (
  name => ['s/\W//g'],
);
%defaults = (
	deleted			=>	0,
	category_id		=>	undef,
	sorting			=>	undef,
	summary_visible	=>	1,
  create_visible => 0,
  view_visible => 0,
	allow_delete	=>	1,
);

sub cache_field {
	return 'name';
}
$cache_field = 'name';

sub next {
	my $self = shift;
	($_) = sql::execute( undef, undef, q{SELECT id FROM Service_Types WHERE name = (SELECT MIN(name) FROM Service_Types WHERE name>?)}, $$self{name} );
	if ( ! $_ ) {
		( $_ ) = sql::execute( undef, undef, q{SELECT id FROM Service_Types WHERE name = (SELECT MAX(name) FROM Service_Types WHERE name<?)}, $$self{name} );
	} # end if
	return $_;
} # end sub next
sub Next {
	return new openprint::ServiceType( $_[0]->next() );
}
sub prev {
	my $self = shift;
	($_) = sql::execute( undef, undef, q{SELECT id FROM Service_Types WHERE name = (SELECT MAX(name) FROM Service_Types WHERE name<?)}, $$self{name} );
	if ( ! $_ ) {
		( $_ ) = sql::execute( undef, undef, q{SELECT id FROM Service_Types WHERE name = (SELECT MIN(name) FROM Service_Types WHERE name>?)}, $$self{name} );
	} # end if
	return $_;
} # end sub prev

sub Prev {
	return new openprint::ServiceType( $_[0]->prev() );
}

sub destroy {
	my $ac = sql::start_transaction( $openprint::dbh );
	sql::execute( undef, undef, q{DELETE FROM tbl_service_defaults WHERE lngServiceTypeIndex=?}, $_[0]{id} );
	sql::update( undef, undef, $openprint::Project_Service::table, [ $openprint::Project_Service::fields{servicetype_id} . ' =?', $_[0]{id} ], $openprint::Project_Service::fields{servicetype_id}, undef );
	sql::execute( undef, undef, q{DELETE FROM Service_Types WHERE id=?}, $_[0]{id} );
	sql::end_transaction( $openprint::dbh, $ac );
} # end sub destroy

sub Category {
	if ( ! $_[0]{Category} ) {
		$_[0]{Category} = new openprint::ServiceType_Category( $_[0]{category_id} );
	}

	return $_[0]{Category};
} # end sub category

sub category {
	if ( @_ == 2 ) {
		my $ServiceType_Category = openprint::ServiceType_Category->find_one('name lc'=>lc $_[1]);
		if ( $ServiceType_Category ) {
			$_[0]{category_id} = $ServiceType_Category->id();
		} else {
			$ServiceType_Category = new openprint::ServiceType_Category();
			$ServiceType_Category->save({ name=>$_[1] });
		} # end if
		$_[0]{Category} = $ServiceType_Category;
		$_[0]{category_id} = $ServiceType_Category->id();
	} # end if

	return $_[0]->Category()->name();
}

sub Defaults {
	if ( ! $_[0]{Defaults} ) {
		$_[0]{Defaults} = [ openprint::ServiceType_Default->find( servicetype_id=>$_[0]{id} ) ];
	}
	return @{$_[0]{Defaults}};
} # end sub Defaults

sub allow_delete {
	if ( @_ > 1 ) {
		$_[0]{allow_delete} = $_[1];
	}
	if ( ! exists $_[0]{allow_delete} ) {
		$_[0]{allow_delete} = $defaults{allow_delete};
	}
	return $_[0]{allow_delete};
}

1;
__END__
