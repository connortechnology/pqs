package eprint::products;
use strict;

use Apache2::Const qw(:common);
use Apache2::Upload ();
use Text::CSV_XS;
use Data::Dumper;
use PQS::Object::product;
use PQS::model::pricing;
use PQS::model::product_filter;
use PQS::model::product_defaults;
use PQS::model::categories;
use PQS::model::product_discount;

use HTTP::Request::Common qw(POST);  
use LWP::UserAgent; 
use SOAP::Lite;
use eprint::project qw(project_allowed get_path has_pdf_template);
use File::Path;
use HTML::Entities;
use ssi;


use Set::CrossProduct;

use constant MAX_DISCOUNT => 5;

sub save_categories {
	my $r = shift;
	map {  
		if ( $_=~ /editname-(\d+)/ ) {
			my $id = $1;
			my $name = $r->param($_);
			my $parent = $r->param("parent-$id") || undef;
			my $active = $r->param("active-$id") || undef;
			print STDERR "SET NAME: $id = $name \n ";
			PQS::model::categories::set_name($id, $name);	
			PQS::model::categories::set_parent($id, $parent);	
			PQS::model::categories::set_active($id, $active);	
		}
	} $r->param();
	if ( $r->param('editname-new') ) {
		my $parent = $r->param("parent-new") || undef;
		my $name   = $r->param("editname-new");
		PQS::model::categories::insert( $parent, $name);

	print STDERR "INSERT NEW $name\n";
	}


}


sub save_filters {
	my $r = shift;

	my $fid = $r->param('fid');
	my $cat = $r->param("cat");
	my $name   = $r->param("filtername");


	$fid = PQS::model::product_filter::set( { name => $name, cat => $cat, id => $fid });

	my @opts =  $r->param('options');

	PQS::model::product_filter::delete_options($fid) if $fid;

	map { 
print STDERR "INSERTING OPTOINS FOR : $fid -- $_ \n ";
		PQS::model::product_filter::insert_option( $_, $fid) if $_;
	} @opts;


}

sub builder { 
	my ($r, $dbh, $var) = @_;

print STDERR "START PRODUCT BUILDER \n";

map { 
	print STDERR "HAVE PARAM: $_ = " . $r->param($_) . " \n";
} $r->param();



	my $fid = $r->param('Edit') || $r->param('fid');
	my $cat = $r->param('cat');

	if ( $r->param('Delete') ) {
		PQS::model::product_filter::delete($fid);
	} elsif ( $r->param('Save')) {
		save_filters($r);
	} elsif ( $r->param('Edit') ) {
		$var->{filter} = PQS::model::product_filter::get($fid);
		$var->{filter}{options} = PQS::model::product_filter::get_options($fid);

		# Add blanks to add new options.
		push @{$var->{filter}{options}}, ( {name => undef}, {name => undef}, {name => undef}); 
	} elsif ( $r->param('New') ) {
		$fid = undef;
		$var->{filter}{name} = 'New';
		$var->{filter}{options} =  [ {name => undef}, {name => undef}, {name => undef}]; 
	}
	

	$var->{filters} = PQS::model::product_filter::get_category($cat);



	my %all;
	map { 
		$_->{options} = PQS::model::product_filter::get_options($_->{id});
		my @ol;
		map { push @ol, $_->{name} } @{ $_->{options} };
		$all{$_->{name}} = \@ol;
	} @{$var->{filters}};


	my $p = new PQS::Object::product;

	$var->{fields} =  $p->update_fields;

	if ( $r->param('Build') ) {
		if ( $r->param('delete_category') ) {
			PQS::model::products::delete_products_in_category($cat);
		}
		build_products($r, $var, \%all);
		insert_products($var->{list}, $cat);
	} elsif ( $r->param('Preview') ) {
		build_products($r, $var, \%all);
	}

	my $template = $dbh->selectcol_arrayref(q{Select name,id FROM tbl_products WHERE category = ?}, undef, $cat);
	$var->{templates} = ssi::make_drop_down($template);


	if ( $r->param('strid') && $r->param('name') ) { 
		PQS::model::product_defaults::delete($cat);

		#Save fields to db.
		map { 
			my $f = $_->{fname}; 
			PQS::model::product_defaults::insert($cat, $f, $r->param($f));
		} @{$var->{fields}};

		foreach my $f ( $r->param() ) {
			if ( $f =~ /min-(.*)/  ) {
				PQS::model::product_defaults::insert($cat, $f, $r->param($f)) if $r->param($f);
			}
			if ( $f =~ /max-(.*)/  ) {
				PQS::model::product_defaults::insert($cat, $f, $r->param($f)) if $r->param($f);
			}
			if ( $f =~ /discount-(.*)/  ) {
				PQS::model::product_defaults::insert($cat, $f, $r->param($f)) if $r->param($f);
			}
		}

	}# else {


	#Load defaults back from db.

		my $defs = PQS::model::product_defaults::get($cat);
		my $map;

		map { 
			my $f = $_->{name}; 
			$var->{$f} = $_->{value};
			$map->{$f} = $_->{value};
		} @{$defs};

		map { 
			push @{$var->{versions}}, 
			{ 	v => $_, 
				min => $map->{"min-$_"}, 
				max => $map->{"max-$_"}, 
				discount => $map->{"discount-$_"}
			}
			
		} (1..MAX_DISCOUNT);

		#}
	

	
	$var->{parents} = ssi::make_drop_down(PQS::model::categories::select_list());
	$var->{fid} = $fid;
	$var->{__FillInForm}{cat} = $cat;

#print STDERR "HAVE StUFF: ", Dumper($var->{list});

}

sub insert_products {
	my $list = shift;

	my $tmp = new PQS::Object::product;
	my @field_list = @{$tmp->update_fields};


	my @discounts;
	my $r = session::r;

	foreach my $f ( $r->param() ) {
		if ( $f =~ /discount-(.*)/  ) {
			print STDERR "AHVE DISCOUNT: $f - $1 \n";
			my $row = [ 
				$r->param("min-$1") || undef,
				$r->param("max-$1") || undef,
				$r->param("discount-$1") || undef,
			];

			push @discounts, $row if @{$row}[2];

		}

	}

	print STDERR "HAVE DISCOUNTS: ", Dumper(\@discounts);



	foreach my $new ( @{$list} ) {


		my $p = new PQS::Object::product;



		foreach my $f ( @field_list ) {
			my $id = $f->{fname};
			my $val = $new->{$id};
			$p->set($id, $val);
			print STDERR "SET ID: $id VAL: $val \n";
		}
		$p->set('category_id', $new->{category});


		map {
			my $oid = PQS::model::product_filter::get_option_id($new->{category}, $_, $new->{$_});
			$p->add_option($oid);
		} @{$new->{filters}};


		$p->validate;
		$p->save;

		PQS::model::product_discount::clear_product($p->{id});
		map { 
			PQS::model::product_discount::insert($p->{id}, @{$_});
		} @discounts;

		next;

		print STDERR "SAVE PRODUCT NEW RPODUCT $new->{key} \n", Dumper($new->{filters});
	}


	



}


sub build_products {
	my ($r, $var, $all) = @_;
	

		sub _sub {
			my $field = shift;
			my $p = shift;
		
			my $x   = $r->param($field);
			my $val = $r->param($field);

			while ( $x =~ /(\[(\w+)\])/g ) {;
			 my $f = "\\\[$2\\\]";
			 my $n = $p->{$2};
			 $val =~ s/$f/$n/;
			
			}
			$p->{$field} = $val;
		}

		
		my $list =  Set::CrossProduct->new($all);

		until ($list->done ) {
			my %p = $list->get;


			my $key;
			map { $key .=  $key ? '-' . $p{$_} : $p{$_}  } sort keys %p;
			$p{key} = $key;

			map { _sub($_->{fname}, \%p) } @{$var->{fields}};

			$p{category} = $r->param('cat');
			$p{filters} = [keys %{$all}];

#print STDERR "HAVE LIST ", Dumper(\%p);
			push @{$var->{list}}, \%p;

		}
}

sub quick_price { 
	my $prod = shift;


}

sub price_admin {
	my ($r, $dbh, $var) = @_;

  
	my $id = $r->param('product');
  
	my $list = PQS::model::pricing::get_list_index('Products');

	my $pricelist = $r->param('pricelist');

	my $p = new PQS::Object::product($id);
  
	if ( $r->param('sell') ) {
  		my $discountable = undef;
		my $min = $r->param('min');
		my $max = $r->param('max');
		my $cost = $r->param('cost') || 0;
		my $sell = $r->param('sell');

		my $price = [$list, $id, $min, $max, $cost, $sell, $discountable, $pricelist];

		PQS::model::pricing::add_price(@{$price});
	} elsif ($r->param('delete') ) { 
		PQS::model::pricing::delete_price($r->param('delete'));

	}

	my $prices = $p->price_export($pricelist);

	$var->{data} = $prices;
	$var->{product} = $id;
	$var->{name} = $p->spec('name');


}

sub category_admin {
	my ($r, $dbh, $var) = @_;
	
print STDERR "START CATEGORY ADMIN \n", Dumper($r->param());
	if ( $r->param('Delete') ) {
		PQS::model::categories::delete($r->param('Delete'));
	} elsif ( $r->param('Save')) {
		save_categories($r);
	}

	my $start =  PQS::model::categories::get_children_from_id(undef, 'show');
	my $list = _children($start, []);
	my $level;



	sub _children { 
		my $childs = shift;
		my $cat = shift;

print STDERR "GOT CHILDREN --  \n", Dumper($childs,$var->{__FillInForm} );

		$level++;


		foreach my $id ( @{$childs}) {

			my $co   = PQS::model::categories::get($id, 'showall1');
			$co->{level} = $level;
			#$var->{__FillInForm}{"parent-". $co->{id}} = $co->{parent};

			push @{$cat}, $co; 

			my $next = PQS::model::categories::get_children_from_id($id, 'showall2');

			_children( $next, $cat) if (@{$next} );
			
		}

		$level--;

		return $cat;

	}
	map {	
		$var->{__FillInForm}{"parent-". $_->{id}} = $_->{parent};
	} @{$list};

	$var->{categories} = $list;

	$var->{parents} = ssi::make_drop_down(PQS::model::categories::select_list());
	

print STDERR "HAVE CATEGORIES: " , Dumper($list, $var->{__FillInForm});
	return;


}
sub kit_select {
  my ($r, $dbh, $var) = @_;


	my $cat  = $r->param('category');
	my $show_all = $r->param('show_all');
	my $kit = $r->param('kit_id');

print STDERR "START KIT SELECT \n";

#	update($r, $dbh, $var) if $r->param('Save');

	my $p = new PQS::Object::product($kit);

	my @items = $r->param('contents');

	if ( $r->param('Save') ) {
		$p->remove_kit_category($cat);
		map { 
			my $qty = $r->param("qty-".$_);
			$p->add_kit_item($_, $qty) if $qty;
		} @items;
	}
		

	my $list = $p->kit_list();

	map {
		push @{$var->{__FillInForm}{contents}}, $_->{id};
		push @{$var->{__FillInForm}{"qty-".$_->{id}}}, $_->{qty};
	} @{$list};

	$var->{kit_contents} = $list;

	$var->{kit} = $p->{specs};


	$var->{products} = PQS::model::categories::products_in_tree($cat, $show_all) if $cat;
	$var->{categories} = ssi::make_drop_down(PQS::model::categories::select_list(), $cat);

	$var->{__FillInForm}{show_all} = $show_all;
	$var->{__FillInForm}{kit_id} = $kit;
		
	$var->{kit_id} = $kit;

	

	print STDERR "HAVE PRODUCTS: ", Dumper($var->{__FillInForm}, $var->{kit});

  
}

#List all products
sub list {
  my ($r, $dbh, $var) = @_;


	my $cat  = $r->param('category');
	my $sort = $r->param('sort');
	my $sort_desc = $r->param('sort_dir');
	my $show_all = $r->param('show_all');


print STDERR "START PRODUCT LIST \n";

	update($r, $dbh, $var) if $r->param('Save');

	PQS::model::products::remove($r->param('delete')) if $r->param('delete');

	importcsv($r, $dbh, $var) 		if $r->upload("import");
	price_import($r, $dbh, $var) 	if $r->upload("price_import");


	$var->{products} = PQS::model::categories::products_in_tree($cat, $show_all) if $cat;

	my $pricelist = 1;

	foreach my $p ( @{$var->{products}} ) {
		foreach my $f (keys %{$p} ) {
			$p->{$f} = HTML::Entities::encode_entities($p->{$f});
		}
		my $data = 	PQS::model::pricing::sell_prices( $pricelist, $p->{id});

		if ( @{$data} <= 1 ) {
			$p->{qprice} = $data->[0]{sell};
		} else { 
			$p->{qprice} = 'noshow';
		}

		print STDERR "HAVE DATA: ", Dumper($data);
	} 

print STDERR "HAVE LIST PRODUCTS: ", Dumper($var->{products});



	my $p = new PQS::Object::product;

	$var->{fields} =  $p->update_fields;

	my @sort_list;
	my $s;

	map{ 
		$s = $_ if $_->{fname} eq $sort;
		push @sort_list, $_->{fname}, $_->{desc}; 
	} @{$var->{fields}};

	$var->{sort} =  ssi::make_drop_down(\@sort_list, $sort);

	$var->{products} = sort_products($var->{products}, $s, $sort_desc);


	exportcsv($r, $dbh, $var) 		if $r->param("export");
	price_export($r, $dbh, $var) 	if $r->param("price_export");

	$var->{categories} = ssi::make_drop_down(PQS::model::categories::select_list(), $cat);

	$var->{__FillInForm}{sort_dir} = $sort_desc;
	$var->{__FillInForm}{show_all} = $show_all;

	print STDERR "HAVE PRODUCTS 1: ", Dumper($s, $sort_desc);

  
}

sub sort_products {

	my ($products, $s, $direction) = @_;

	my $sort = $s->{fname};

	if ( $s->{type} eq 'int' ) {
		if ( $direction eq 'desc' ) {
			$products = [ sort {$b->{$sort} <=> $a->{$sort} } @{$products} ];
		} else {
			$products = [ sort {$a->{$sort} <=> $b->{$sort} } @{$products} ];
		}
	} else { 
		if ( $direction eq 'desc' ) {
			$products = [ sort {$b->{$sort} cmp $a->{$sort} } @{$products} ];
		} else {
			$products = [ sort {$a->{$sort} cmp $b->{$sort} } @{$products} ];
		}
	}

	return $products;

}


#update existing products
sub update {
  my ($r, $dbh, $variable) = @_;
  my $param = $r->param;

  
  my $temp = new PQS::Object::product();

  my @field_list = $temp->field_list();

  foreach my $key ( $r->param('productid')) {

	my $p = new PQS::Object::product($key);

	foreach my $f ( @field_list ) {
		my $val = $r->param("$f\[$key\]");
		$p->set($f, $val);
	}

	$p->validate;
	$p->save;

  }

	if ( $r->param('strid') ) {
		my $p = new PQS::Object::product();
		foreach my $f ( @field_list ) {
			my $val = $r->param("$f");
			print STDERR "UPDATTE F: $f = $val \n";
			$p->set($f, $val);
		}
		$p->set('category_id', $r->param('category'));

		$p->validate;
		$p->save;
	}


}


sub details {
	my ($r, $dbh, $var) = @_;
	 
	my $id = $r->param('id');
	my $cust_id = $var->{cust_id};

	my $p = new PQS::Object::product($id);
	$var->{product} = $p->specs();
	$var->{prices} = $p->prices($cust_id);

	$var->{kit_list} = $p->kit_list();

	$var->{product}{image}  = $p->image(1);
 
 print STDERR "HAVE PRODUCT DETAILS  FOR ID: $id ", Dumper($var->{product});

	
}

sub preconfig {
    my $host	    = shift;
    my $key	    	= shift;
    my $template    = shift;
    my $product	    = shift;
    my $qty	    	= shift;
    my $ocid	    = shift;



    my $back   = "http://$host/main/ecommerce/products.html";
    my $return = "http://$host/main/order/order_submit.html?MW_Return=$ocid";
    my $username = "PersonaPizzaSDK";

    my $ua = LWP::UserAgent->new();  

    my $content = qq{
    <XmlHttpRequestData>
    <GenericRequest SessionKey="$key">
    <RequestFor>UpdatePreConfigureAdvertRequest</RequestFor>
    <PreConfigureAdvertRequest><ReturnUrl>$return</ReturnUrl>
    <BackUrl>$back</BackUrl>
    <Jobname>AdName</Jobname>
    <UserInfo>
	    <UserId></UserId>
	    <LoginName>$username</LoginName>
    </UserInfo>
    <TemplateDetails><ID>$template</ID></TemplateDetails><Action>NEW</Action>
    <AdDescription></AdDescription><ReturnAction>REDIRECT</ReturnAction>
    <DisplayLayerPalette>N</DisplayLayerPalette>
    </PreConfigureAdvertRequest></GenericRequest>
    </XmlHttpRequestData>
    };

    my $req = POST 'http://selfservice.mediawide.com/pnsdk/pnsdk_complex.asmx/Generic', [ XmlHttpRequestData => $content ]; 

    my $response = $ua->request($req)->as_string; 

}

sub mw_auth {

    my $soap = SOAP::Lite->new( proxy=>'http://selfservice.mediawide.com/pnsdk/pnsdk_complex.asmx');

    $soap->on_action( sub { "http://www.publish-now.biz/PNSDK/PNSDK/AuthenticateUser" });
    $soap->default_ns('http://www.publish-now.biz/PNSDK/PNSDK');

    my $content = q{<AuthenticateUserRequest>
	    <UserName xmlns="">PersonaPizzaSDK</UserName>
	    <Password xmlns="">password</Password>
	  </AuthenticateUserRequest>};


    my $elem = SOAP::Data->type('xml' => $content);

    my $r = $soap->AuthenticateUser($elem);

    return $r->result->{SessionID};
}


sub design {
    my ($r, $dbh, $var, $cookie) = @_;
    my $template    = $r->param('mediawide');
    my $product	    = $r->param('product');
    my $qty	    = $r->param('txtQuantity1');

    my $session = mw_auth();

    my $host = $r->headers_in->{'Host'};


    my ($orderid, $ocid) = eprint::order::add_product_to_order( $cookie, $var, $product, $qty );

	my $prod = PQS::model::products::get($product);

	my ($pid) = eprint::print_project::copy_project($dbh, $var, $prod->{project});
print STDERR "HAVE PRODUCT PID: $pid FOR: $prod->{id} OCID: $ocid   \n", Dumper($prod);

	PQS::model::order::set_mw_session($ocid, $session);

	PQS::model::order::set_spec_pid($ocid, $pid);

    preconfig($host, $session, $template, $product, $qty, $ocid);

    $var->{SessionID} = $session;


}


sub get_highres_file {

	my $jobid 	= shift;
	my $key   	= shift;
	my $pid		= shift;
	my $oid		= shift;
	
	my $dbh = session::dbh;

	my $soap = SOAP::Lite->new( proxy=>'http://selfservice.mediawide.com/pnsdk/pnsdk_complex.asmx');

    $soap->on_action( sub { "http://www.publish-now.biz/PNSDK/PNSDK/CreateHighResPDF" });
    $soap->default_ns('http://www.publish-now.biz/PNSDK/PNSDK');

	my $content = qq{
		<CreateHighResPDFRequest  SessionKey="$key" PageType="Multiple" >
			<DAPType xmlns="">ROPI</DAPType>
			<PNJobID xmlns="">$jobid</PNJobID>
			<StyleName xmlns=""><![CDATA[hires.joboptions]]></StyleName>
			<IccProfile xmlns=""><![CDATA[daily gloss.csf]]></IccProfile>
		</CreateHighResPDFRequest>
	};


	my $elem = SOAP::Data->type('xml' => $content);

    my $r = $soap->CreateHighResPDF($elem);

	my $path = $r->result->{OutputFilePaths}{FileUrl};

	my $ua = LWP::UserAgent->new;

	my $response = $ua->get($path);
	
    my $projdir    = get_path(undef, $dbh, $pid);

	mkpath($projdir);

	my $f = "$projdir/${oid}_$pid.pdf";

	open ( my $FH, '>', $f) or die "Could not open file";
	print $FH $response->content;
	close $FH;

}




sub display {
 my ($r, $dbh, $var) = @_;
 
	my $cat 	= $r->param('category');
	my $qty 	= $r->param('quantity');
	my $cid 	= $var->{cust_id} || 1;
	my $log 	= session::log;
	my $product = $r->param('product');
	my $versions = $r->param('versions') || 1;

	$cat = configuration::get_value($log, $dbh, 'Default Product Category') unless $cat;

	if ( $product ) { 
		my $p = new PQS::Object::product($product);
		$cat = $p->spec('category_id');
		print STDERR "LAOD PRODUCT: $product, CAT=$cat \n", Dumper($p->{specs});
	}
  
	#Set categories for left nav.
	my $cats = PQS::model::categories::get_all();

	map { push @{$var->{categories}}, $cats->{$_}; } sort keys $cats;


	#Create category chain for parents of current category.
	my $parent = $cat;
	my $name =  PQS::model::categories::get_name_from_id($parent);    
	push @{$var->{cat_chain}}, { id => $parent, name => $name};


	print STDERR " CAT CHAIN " , Dumper($var->{cat_chain});

	while ( $parent ) {
		$parent = PQS::model::categories::get_parent_from_id($parent);

		next unless $parent;
		$name =  PQS::model::categories::get_name_from_id($parent);    

		unshift @{$var->{cat_chain}}, { id => $parent, name => $name};
	}


	#Get children for current cat.
	my $childs =  PQS::model::categories::get_children_from_id($cat);

	map {
		my $c = PQS::model::categories::get($_);
		print STDERR "HAVE CAT: " , Dumper($c);
		push @{$var->{cat_children}}, $c;
	} @{$childs};


   #Show products for first Child category if it exists.
   #Parent Categorys should not have products under sherwood model.
   $cat = @{$childs}[0] if  @{$childs};


  	if ( $product ) {
		#skip straight to the product we are looking for.
		push	@{$var->{products}}, PQS::model::products::get($product);
	} else { 
		#products of of current and all children cats.
		$var->{products} =  PQS::model::categories::products_in_tree($cat, $product);
	}

	
	
	$var->{products} = filter_products($r, $var, $var->{products});


	my $total_qty 	= $qty * $versions;

	foreach my $p (@{$var->{products}} ) {

		my $prod = new PQS::Object::product($p->{id});

		unless ($qty ) {
			if ( $prod->{specs}{units} eq 'Per 1000' ) {
				$qty = 1000;
			} else {
				$qty = 1;
			}
		}

		$p->{category} = PQS::model::categories::get_name_from_id($p->{category});

		my $price 		= $prod->price($cid, $qty, $versions);

		$p->{price} = $price * $total_qty;

		$p->{image}  = $prod->image(1);
  
  	}
	
	my $filters =  PQS::model::product_filter::get_category($cat);

	foreach my $f (@{$filters}) {
		$f->{options} = PQS::model::product_filter::get_options($f->{id});
	}

	#IF a product id is supplied, set the filter options to match that product.
	if ( $product ) {

		my $list = PQS::model::product_filter::options_for_product($product);

		map {
			$var->{__FillInForm}{"filter-$_->{filter}"} = $_->{opt};
		} @{$list};
	}

	$var->{filters} 		= $filters;
	$var->{cat} 			= $cat;
	$var->{quantity} 		= $r->param('quantity') || $qty;
	$var->{total_quantity} 	= $total_qty;
	$var->{versions} 		= $versions;

}


sub filter_products {
	my ($r, $var, $prods ) = @_;

	my @valid;
	my @list;
	my $have_filter ;
	map {
		if ( $_ =~ /filter-(\d+)/ && $r->param($_) ) {
			my $fid = $1;
			my $oid = $r->param($_);
			$have_filter = 1;

			$var->{__FillInForm}{"filter-$fid"} = $oid;

			my $match = PQS::model::product_filter::products_with_option($oid);
			if ( @list ) {
				my @newlist;
				foreach my $m (@{$match}) {
					my $valid = grep(/$m/, @list);
					push @newlist, $m if $valid;
				}
				@list = @newlist;
				
			} else {
				@list = @{$match};
			}

			print STDERR "HAVE FILTER: $oid \n", Dumper($match, \@list);
		}
	} $r->param();

	my @plist;


	foreach my $p (@{$prods} ) {
		push @plist, $p if grep {$p->{id} eq $_} @list;
	}

#print STDERR "HAE PRODUCTS: ", Dumper($have_filter, @plist, $prods);
	
	return $have_filter ? \@plist : $prods;
	

}




  
#Get details on a single product
sub get {
  my ($r, $dbh, $variable, $id) = @_;
  $id = $r->param('id') unless $id;
  return SERVER_ERROR unless $id;
  $variable->{product} = $dbh->selectall_arrayref("select * from tbl_products where id = ?", $id);
}


sub exportcsv {
  my ($r,  $dbh, $var) = @_;
  
	my $list = $var->{products};

	my $h = new PQS::Object::product();
	my @data = [$h->import_fields];

	foreach my $product ( @{$list} ) {
		my $p = new PQS::Object::product($product->{id});

		push @data, $p->csv_export;
	
	}

	print STDERR "HAVE EXPORT DATA" , Dumper(\@data);
	my $log = session::log;
	misc::export_csv( $r, $var, 'products.csv',  \@data );

}


#import a CSV of products
sub importcsv {
  my ($r, $dbh, $variable) = @_;
  my $csv = Text::CSV_XS->new({binary => 1});
  my $fh = $r->upload("import")->fh; 
  
  my $header = $csv->getline($fh);
  
  while (my $row = $csv->getline($fh)) {

	my $p = new PQS::Object::product();

	$p->csv_import($header, $row);

	print STDERR "HAVE SPECS: " , Dumper($p->{specs});

	my $valid = $p->validate();
	$p->save() if $valid;

  }
  close $fh;
}

#import a CSV of products
sub price_export {
	my ($r, $dbh, $var) = @_;
	
	my @data  = [qw(strid min max cost sell)];

	my $pricelist = $r->param('pricelist');


	my $products = $var->{products};

print STDERR "START PRICE EXPORT: ", Dumper($products);


	foreach my $id (@{$products}) { 
		my $p = new PQS::Object::product($id->{id});


		my $prices = $p->price_export($pricelist);

		$prices = [{}] unless @{$prices};


		map {	push @data,  
			[ $p->spec('strid'), $_->{min}, $_->{max}, $_->{cost}, $_->{sell} ]
		} @{$prices};

	}
	
	my $log = session::log;

	misc::export_csv( $r,  $var, 'pricing.csv', \@data );


}


  


#import a CSV of products
sub price_import {
  my ($r, $dbh, $variable) = @_;
  
  print STDERR "START PRICE IMPORT NOW \n";
  
  my $csv = Text::CSV_XS->new({binary => 1});
  my $fh = $r->upload("price_import")->fh;
  
  my $list = PQS::model::pricing::get_list_index('Products');

  my $pricelist = $r->param('pricelist');
  
  my $header = $csv->getline($fh);
  
  my $discountable = undef;
  my $data;
  my $line;
  
  while (my $row = $csv->getline($fh)) {
	$line++;
	my $id =  PQS::model::products::get_id_from_str($row->[0]);
	die("Invalid Product ID: $row->[0] Row: $line") unless $id;
    $row->[0] = PQS::model::products::get_id_from_str($row->[0]) if $header->[0] eq 'strid';

    #( $row->[3] ) = $row->[3] =~ m{(\d+\.\d+)};
    #( $row->[4] ) = $row->[4] =~ m{(\d+\.\d+)};

	push @{$data->{$row->[0]}}, [$list, @{$row}, $discountable, $pricelist];

  
  }

print STDERR "INSERTING PRICE: ", Dumper($data);

  	map { 
		my $id = $_;
  		PQS::model::pricing::clear_item($id, $pricelist);
		foreach my $price ( @{$data->{$id}} ) {
    		PQS::model::pricing::add_price(@{$price});
		}
		
	} keys %{$data};


  close $fh;
}



sub record_error {
  my $red = shift;
}

1;
