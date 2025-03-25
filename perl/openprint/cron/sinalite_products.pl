#!/usr/bin/perl 
use lib '/var/www/testing/perl';
use 5.10.0;
use utf8;

# INCLUDES
use strict;
use warnings;

use WWW::Mechanize;
use CGI qw/:standard/;
use HTML::TreeBuilder;
use JSON;
use File::Slurp;
use File::Basename;

use Data::Dumper;
require configuration;
require sql;
require ssi;
require misc;
require openprint::Company;
require openprint::User;
require Email::Valid;
require openprint::Email;
require logger;
require openprint::Wall;
require Date::Parse;
require Date::Format;
require openprint;
require openprint::Product;
require openprint::Product_Category;
require openprint::Object_Specification;
require openprint::Pricelist;

use vars qw( $log $dbh %config );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use File::Basename qw(basename);
use Getopt::Long;
use Mail::Sendmail;
use MIME::QuotedPrint;
use Time::HiRes qw(usleep);
use Encode qw(encode);

my $program = basename($0);

my @args = @ARGV;

my $opts = {};
GetOptions($opts, 'help', 'log_file=s', 'log_level=s', 'markup=s', 'interactive=s',
	'db_name=s', 'db_host=s', 'db_user=s', 'db_pass=s', 'db_port=s',
 );

if ($opts->{help}) {
	usage();
	exit 0;
}

$log = new logger( {level=>'debug'});
# Get our configuration information
configuration::from_file("/etc/openprint/$program.conf");
configuration::merge( $opts );
$log->level($config{log_level}) if $config{log_level};

# Declare variables
foreach my $param ( 'db_name','db_user','db_pass' ) {
	if ( ! $config{$param} ) {
		die "$program: missing required --$param parameter";
	}
} # end foreach required-param
$openprint::dbh = sql::open_sql( $log, 
	host		=> $config{db_host},
	port		=> $config{db_port},
	database	=> $config{db_name},
	driver	=> 'Pg',
	login		=> $config{db_user},
	password	=> $config{db_pass},
);
die 'Error opening db' if ! $dbh;
configuration::init();
configuration::merge( $opts );
openprint::session_init();

if ( ! $openprint::Pricelist ) {
  $openprint::Pricelist = openprint::Pricelist->find_one(name=>'default');
}

my $host = 'https://sinalite.com';

my $mech = WWW::Mechanize->new();
$mech->get($host.'/en_ca/customer/account/login');

$mech->submit_form(
    form_id => 'login-form',
    fields    => { 
      'login[password]'		=>	'pakistan',
      'login[username]'		=>	'imran@muizgraphics.com',
    },
    button	=>	'send',
    );
#print $mech->content();
my $all_products_content;

print "Getting $host/en_ca/all-products.html\n";
if ( -e "/tmp/all-products.html" ) {
	print "Using cached content...\n";
	$all_products_content = read_file( "/tmp/all-products.html", ,err_mode => 'carp' );
} 
if ( ! $all_products_content ) {
	print "Not Using cached content...\n";
	$mech->get($host.'/en_ca/all-products.html');
	$all_products_content = encode( 'utf-8', $mech->content() );
	write_file( '/tmp/all-products.html', { atomic => 1, err_mode=>'carp', binmode => ':raw' }, $all_products_content );
}

print "parsing...";
my $tree = HTML::TreeBuilder->new ( p_strict=>1, warn=>1, implicit_tags=>0 );
$tree->parse($all_products_content);
$tree->eof();
$tree->elementify();
print "done\n";

my $Root = openprint::Product_Category->find_one(name=>'Products');
if ( ! $Root ) {
	$Root = new openprint::Product_Category();
	$Root->save({name=>'Products'});
}

my $menu_order = 0;
# First step: Setup all the categories from the mnu
foreach my $menu ( $tree->look_down(_tag=>'ul', class=>'em-catalog-navigation') ) {
	print "Have menu " . $menu->as_HTML() . "\n";
	my @items = $menu->look_down( _tag=>'li', sub { $_[0]->attr('class') =~ /level0/; } );
	print "Found " . @items . " menu items\n";
	$menu_order += 1;

	foreach my $item ( @items ) {
		my $name = $item->look_down( _tag=>'span' )->as_text();
		next if $name eq '>';
		print "Have item $name\n";
		my $MainCategory = openprint::Product_Category->find_one(name=>openprint::Product_Category->transform(name=>$name));
		if ( ! $MainCategory ) {
			if ( confirm( "Add main category $name ? (Y|n)" ) ) {
				$MainCategory = new openprint::Product_Category();
				$MainCategory->save({name=>$name});
			} else {
				next;
			}
		} else {
			if ( ! ( $MainCategory->parent_ids() and sets::isin( $Root->id(), $MainCategory->parent_ids() ) ) ) {
				$MainCategory->save({parent_ids=>[ ( $MainCategory->parent_ids() ? @{$MainCategory->parent_ids()} : () ), $Root->id() ] });
			}
		} 
		foreach my $subitem ( $item->look_down( _tag=>'li', sub { $_[0]->attr('class') =~ /level1/ }) ) {
			my $subname = $subitem->look_down( _tag=>'span' )->as_text();
			my $SubCategory = openprint::Product_Category->find_one(name=>openprint::Product_Category->transform(name=>$subname) );
			$log->debug("Sub Category $subname");
			if ( ! $SubCategory ) {
				if ( confirm( "Add sub category $subname ? (Y|n)" ) ) {
					$SubCategory = new openprint::Product_Category();
					$SubCategory->save({ name=>$subname, parent_ids=>[$MainCategory->id()] });
				}
			} elsif ( ! ( $SubCategory->parent_ids() and sets::isin( $MainCategory->id(), $SubCategory->parent_ids() ) ) ) {
				$SubCategory->save({ parent_ids=>[ ( $SubCategory->parent_ids() ? @{$SubCategory->parent_ids()} : () ), $MainCategory->id() ] });
			}

			foreach my $product_item ( $subitem->look_down( _tag=>'li', sub { $_[0]->attr('class') =~ /level2/ } ) ) {
				my $product_name = $product_item->look_down( _tag=>'span' )->as_text();
				$log->debug("Product $product_name");
				my $Product = openprint::Product->find_one(name=>openprint::Product->transform(name=>$product_name) );
				if ( ! $Product ) {
					if ( confirm( "Add product $product_name ? (Y|n)" ) ) {
						$Product = new openprint::Product();
						$Product->save({name=>$product_name, category_id=>$SubCategory->id() });
					} else {
						next;
					}
				} elsif ( ! $Product->category_id() ) {
					$Product->save({ category_id=>$SubCategory->id() });
				}
			} # end foreach product
		} # end foreach subitem
	} # end foreach item
  #confirm();
  last; # We only want the first ul with that class
}

foreach my $category ( $tree->look_down('class','all-products') ) {
	my $product_name_h2 = $category->look_down('class','product-name');
	my $product_name_a = $product_name_h2->look_down(_tag=>'a');
	my $url = $product_name_a->attr_get_i('href');
	print "$url \n";
	print $product_name_a->as_text()."\n";

	my $filename = basename( $url );
	my $content = '';
	if ( -e "/tmp/$filename" ) {
		$content = read_file( "/tmp/$filename" );
	} 
	if ( ! $content ) {
		$mech->get($url);
		$content = encode( 'utf8', $mech->content() );
		write_file( "/tmp/$filename", { atomic => 1, err_mode=>'carp', binmode => ':raw' }, $content );
	}
	my $product_tree = HTML::TreeBuilder->new;
	$product_tree->parse_content( $content );
	$product_tree->elementify();

	my $first_div = $product_tree->look_down(id=>'firstDiv');
	my $header = $first_div->look_down(id=>'product-header');
	my $name = $header->look_down(_tag=>'h1')->as_text();
	
	my ( $type_p, $description_p ) = $first_div->look_down(_tag=>'p');
	my $type = $type_p->as_text() if $type_p;
	my $description = $description_p->as_text() if $description_p;

	my $Category = openprint::Product_Category->find_one( name=>$name );
	if ( ! $Category ) {
    if ( confirm( "Add product category $name?" ) ) {
      $Category = new openprint::Product_Category();
      $Category->save({ name=>$name, description=>$description });
    }
	} else {
		$description = $Category->transform(description=>$description);

		if ( $Category->description() ne $description ) {
			if ( confirm( "Update description from\n$$Category{description}\n\nto\n\n$description\n? (Y/n)" ) ) {
				$Category->save({ description=>$description });
			}
		}
	}
$log->debug(" $$Category{name} $$Category{id} ");
	my %category_specs = map { $$_{name} => $_ } $Category->Specifications();

	foreach my $spec ( $first_div->look_down( id=>'product-spec' ) ) {

		my $title_div = $spec->look_down( id=>'spec-title' );
		my $title = Encode::encode('utf-8', $title_div->look_down( _tag=>'p' )->as_text() ) if $title_div;
		my $value_div = $spec->look_down(id=>'spec-info');
		if ( ! $value_div ) {
			print "No value_div for $title\n";
			next;
		}
		my $value_p = $value_div->look_down(_tag=>'p');
		my $value;
		if ( ! $value_p ) {
			$value = $value_div->as_trimmed_text();
			print "No value_p for $title, using the html version of div content\n$value\n";
		} else {
			$value = $value_p->as_trimmed_text();
			print "Had value_p for $title, using the html version of p content\n$value\n";
		}
		$value =~ s/”/"/g;
		$value =~ s/–/-/g;
		$value = Encode::encode('utf8', $value );

		$title = openprint::Object_Specification->transform(name=>$title);
		$value = openprint::Object_Specification->transform(value=>$value);

		my $Spec;
		if ( ! $category_specs{$title} ) {
			if ( confirm( "add specification $title = $value ? (Y|n)" ) ) {
				my $Spec = new openprint::Object_Specification();
				$Spec->save({ Object=>$Category, name=>$title, value=>$value });
				$category_specs{$title} = $Spec;
            }
		} else {
			$Spec = $category_specs{$title};
      $Spec->save();
			if ( $$Spec{value} ne $value ) {
				if ( confirm( "Change specification $title from\n\n$$Spec{value}\n\nto\n\n$value\n\n ? (Y|n)" ) ) {
					$Spec->save({ value=>$value });
					$category_specs{$title} = $Spec;
        } else {
          $log->debug("No need to change spec value for $title $value");
				}
			}
		}
	} # end foreach spec

	my $second_div = $product_tree->look_down(id=>'secondDiv');
	my $product_container = $product_tree->look_down(id=>'productContainer');
	if ( ! $product_container ) {
		print "No product_container\n";
		print $second_div->as_HTML();
		next;
	}
	my $objData;
	foreach my $script ( $product_tree->look_down(_tag=>'script') ) {
		my $text = $script->as_HTML();
		if ( $text =~ /var objData=([^;]+);'/ ) {
			$objData = decode_json( $1 );
			last;
		} elsif ( $text =~ /price_template\.init\('[^']+', '([^']+)/m ) {
			$objData = decode_json( $1 );
			last;
		} elsif ( $text =~ /price_template/ ) {
			print $text."ERROR\n";
		}
	} # end foreach script
	if ( $objData ) {
	} else {
		print "No objData press any key to continue\n";
		<STDIN>;
		next;
	}
	foreach my $type ( keys %{$objData} ) {
		my $blah = $$objData{$type};

		my $fields = $$blah{fields};
		
		my $product = $$fields{Product};
		if ( $$fields{Product} ) {
			$product = $$fields{Product};
		} elsif ( $$fields{Stock} ) {
			$product = $$fields{Stock};
		}	
  
    $log->debug("Type: $type");
		print Data::Dumper::Dumper( $product ) . "\n";

		foreach my $name_key ( keys %{$product} ) {
			my $name;
			if ( $name_key =~ /Product_(.*)/ ) {
				$name = $1;
			} elsif ( $name_key =~ /Stock_(.*)/ ) {
				$name = $1;
			}

			parse_tree( $Category, $name, {}, $$product{$name_key} );

		} # end foreach product_type
	} # end foreach product_name
	confirm( "Hit enter to continue..." );
} # end foreach post

sub parse_tree {
	my ( $Category, $name, $product, $tree ) = @_;
	
	print 'tree: ' . join(',', keys %{$tree} ) . "\n";

	
	foreach my $key ( keys %{$tree} ) {

		if ( $key eq 'qty' or $key eq 'eachorlot' ) {			
			my $product_name = join(' ', $name, @$product{sort { $a cmp $b } keys %{$product} } );
			$log->debug("Have qty/eachorlot $key product $product_name");
			my $Product = openprint::Product->find_one( name=>openprint::Product->transform(name=>$product_name) );
			if ( ! $Product ) {
				if ( confirm( "Add Product $product_name ? (Y|n)" ) ) {
					$Product = new openprint::Product();
					$Product->save({name=>$product_name});
				} else {
					return;
				}
      } else {
        if ( ! $Product->category_id() ) {
          $log->debug("Setting category on $$Product{id} $$Product{Name} ");
          $Product->save({ category_id => $Category->id() });
        } elsif ( $Product->category_id() != $$Category{id} ) {
          if ( confirm("Update category on product $$Product{id} $$Product{name} from " . $Product->Category()->name() . " to " . $Category->name() ) ) {
            $Product->save({ category_id => $Category->id() });
          }
        } else {
          $log->debug("Setting category on $$Product{id} $$Product{Name} ");
        }
			}
			my %product_specs = map {$$_{name} => $_} $Product->Specifications();
			foreach my $spec ( keys %{$product} ) {
				my $Spec = $product_specs{$spec};

				if ( ! $Spec ) {
					if ( confirm( "Add spec for $spec on $product_name ? (Y|n)" ) ) {
						$Spec = new openprint::Object_Specification();
						$Spec->save({Object=>$Product, name=>$spec, value=>$$product{$spec} });
						$product_specs{$spec} = $Spec;
					}
        } else {
          utf8::decode($$product{$spec});
$log->debug("Already have spec $spec => $$product{$spec}" );
          if ( $Spec->value() ne $$product{$spec} ) {
            if ( confirm( "Update spec $spec from $$Spec{value} to $$product{$spec}" ) ) {
              $Spec->save({ value => $$product{$spec} });
            }
          }
				}
			} # end foreach spec

			my $qty_hash = $$tree{qty};
			my %product_prices = map { $$_{min} => $_ } $Product->Prices();
			foreach my $qty_key ( keys %{$qty_hash} ) {
				my ( $qty ) = $qty_key =~ /^qty_(\d+)$/;
				my $cost = Math::Round::nearest( 0.01, $$qty_hash{$qty_key} );

	my $units = '';
	if ( $$tree{eachorlot} ) {
		$units = $$tree{eachorlot}
  } elsif ( $$tree{qty_each_lot} ) {
    $units = $$tree{qty_each_lot}{$qty_key};
	}
				#if ( $cost != Math::Round::nearest( 0.01, $cost ) ) {
					#print "Rounding cost from $cost to " . Math::Round::nearest( 0.01, $cost  ) . "\n";
					#$cost = Math::Round::nearest( 0.01, $cost );
				#}

				my $Price = $product_prices{$qty};
				#$Price = $Product->get_Price( $qty ) and ! $Price;
$$Price{cost} = 1*$$Price{cost};
			
				if ( ! $Price ) {
					if ( confirm( "Add Price for $qty $units $cost on $product_name ? (Y|n)" ) ) {
						$Price = new openprint::ProductPrice();
						$Price->save({product_id=>$Product->id(), min=>$qty, max=>$qty, units=>$units, cost=>$cost, pricelist_id=>$$openprint::Pricelist{id}, owner_id=>$config{owner_id}, price=>$cost });
					}
				} else {
					if ( ( $$Price{cost} != $cost ) or ( $$Price{units} ne $units ) ) {
						if ( confirm( "Price has changed $product_name for $qty from ($$Price{cost})$$Price{units} to ($cost) $units Update? (Y|n)" ) ) {
							$Price->save({ units=>$units, cost=>$cost, price=>$cost*$$Price{markup} });
						}
          #} else {
            #$log->debug("No need to update pricing");
					}

				} # end if no prices

			} # end foreach qty_key
		} else {
			print "Recursing for key $key: " . join(',', keys %{$$tree{$key}} ) . "\n";
			# It' something other than qty or eachorlot
			foreach my $option ( keys %{$$tree{$key}} ) {
				if ( ref $$tree{$key}{$option} ne 'HASH' ) {
					#print "Not recursing because there is no subtree for $option $$tree{$key}{$option}\n";
					next;
				}
		
				my ( $value ) = $option =~ /^${key}_(.*)/;
				print "Got $value for $option\n";
				$$product{$key} = $value;
        print Data::Dumper::Dumper( $$tree{$key}{$option} ) . "\n";
				parse_tree( $Category, $name, $product, $$tree{$key}{$option} );
			}
		} # end if it's the qty
		
	} # end foreach key
} # end sub parse_tree

sub confirm {
	if ( $$opts{interactive} ) {
		my $input;
		print $_[0];
		$input = <STDIN>;
		chomp $input;
		if ( $input eq 'Y' or $input eq '' ) {
			return 1;
		}
		return 0;
	} else {
		return 1;
	}
	return 0;	
}

1;
__END__
