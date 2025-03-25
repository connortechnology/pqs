use strict;
require openprint::Log;
require openprint::Product;
require openprint::ProjectType;
package openprint::Product_Category;
our @ISA = qw( openprint::Object );
use vars qw( $debug $serial $table %fields %transforms %defaults );

$debug = 1;
$serial = 'product_categories_id_seq';
$table = 'Product_Categories';

%fields = (
		id							=>	'id',
		name						=>	'name',
		description			=>	'description',
    #projecttype_id	=>	'projecttype_id',
		parent_ids			=>	'parent_ids',
		sorting					=>	'sorting',
		deleted					=>	'deleted',
		album_id        =>  'album_id',
);

%transforms = (
    id								=>	[ 's/\D//g', '<2147483647' ],
    name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
    );
%defaults = (
		deleted					=>	0,
		parent_ids			=>	undef,
    #projecttype_id	=>	undef,
		sorting					=>	undef,
		album_id				=>	undef,
);

sub destroy {
	my $self = shift;
	return if ! $$self{id};
	my $error = '';
	my $ac = sql::start_transaction( $openprint::dbh );
  foreach my $Category ( $self->Categories() ) {
    $error .= $Category->save({parent_ids=>sets::exclude([$Category->id()], $Category->parent_ids())});
  }
	foreach my $Product ( openprint::Product->find(category_id=>$$self{id}, deleted=>[0,1]) ) {
		$error .= $Product->save({category_id=>undef});
	} # end foreach
	$error .= $self->SUPER::destroy();
	sql::end_transaction( $openprint::dbh, $ac );

	# Add record to audit log - action "Delete Product Category".
	new openprint::Log()->save({action=>'Delete Product Category', note=> "Product Category ID: $$self{id} Name: $$self{name}"});
	return $error;
} # end sub destroy

sub products {
  Carp::cluck("Deprecated call openprint::Product_Category::products");
  return $_[0]->Products();
} # end sub products

sub Products {
  my $self = shift;
  if ( $$self{id} ) {
    my %params = @_;
    $params{category_id} = $$self{id};

    return openprint::Product->find( %params );
  }
  return ();
} # end sub products

sub Photos {
  if ( ! $_[0]{album_id} ) {
    return ();
  } # end if
  return $_[0]->Album()->Photos( );
} # end sub Photos

sub Album {
  my $Album = new openprint::Photo_Album( $_[0]{album_id} );
  if ( ! $Album->id() ) {
    $Album->name('Photos for product '.$_[0]{name});
    #$Album->save();
  } # end if
  return $Album;
} # end sub Album

sub url_to {
  return '/product/category_view.html?category_id='.$_[0]{id};
}
sub link_to {
  return sprintf('<a href="/product/category_view.html?category_id=%d">%s</a>', $_[0]{id}, @_ > 1 ? $_[1] : $_[0]{name} );
}

sub parent_id {
  my $self = shift;
  my $parent_ids = $self->parent_ids();
  if ($parent_ids and @{$parent_ids}) {
    return $$parent_ids[0];
  }
  return undef;
}

sub parent_ids {
  my $self = shift;
  if ( @_ ) {
    if ( ref $_[0] eq 'ARRAY' ) {
      $$self{parent_ids} = [ map { $_ =~ /(\d+)/ } @{$_[0]} ];
    } else {
      $$self{parent_ids} = [ map { $_ =~ /(\d+)/ } @_ ];
    }
  }
  return @{$$self{parent_ids}} if wantarray;
  return $$self{parent_ids};
}

sub Parent {
  my $self = shift;
  my $parents = $self->Parents();
  if (@{$parents}) {
    return $$parents[0];
  }
  return undef;
}

sub Parents {
	if ( ! $_[0]{Parents} ) {
		$_[0]{Parents} = ($_[0]{parent_ids} and @{$_[0]{parent_ids}}) ? [ openprint::Product_Category->find('id in'=>$_[0]{parent_ids})] : [];
	}
	return @{$_[0]{Parents}} if wantarray;
	return $_[0]{Parents};
}

sub children {
return $_[0]->Categories();
}
sub Categories {
	if ( ! $_[0]{Categories} ) {
		$_[0]{Categories} = [ openprint::Product_Category->find( 'parent_ids @>'=>$_[0]{id}, order=>'sorting, lower(name)' ) ];
	}
	return @{$_[0]{Categories}};
} # end sub Categories

sub upload {
	my $self = shift;
	my $Album = $self->Album();
	if ( ! $Album->id() ) {
		$Album->save();
		$$self{album_id} = $Album->id();
		$self->save();
	}
	return $Album->upload(@_);
} # end sub upload

sub thumbnail_id {
return undef;
}

1;
__END__
