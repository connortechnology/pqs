package eprint::products;
use strict;

use Apache2::Const qw(:common);
use Apache2::Upload ();
use Text::CSV_XS;
use Data::Dumper;
use PQS::Object::product;
use PQS::model::pricing;
#use PQS::model::product_filter;

use HTTP::Request::Common qw(POST);  
use LWP::UserAgent; 
use SOAP::Lite;
use eprint::project qw(project_allowed get_path has_pdf_template);
use File::Path;
use HTML::Entities;
use ssi;


sub save_categories {
	my $r = shift;
	map {  
		if ( $_=~ /editname-(\d+)/ ) {
			my $id = $1;
			my $name = $r->param($_);
			my $parent = $r->param("parent-$id");
			print STDERR "SET NAME: $id = $name \n ";
			PQS::model::categories::set_name($id, $name);	
			PQS::model::categories::set_parent($id, $parent);	
		}
	} $r->param();
	if ( $r->param('editname-new') ) {
		my $parent = $r->param("parent-new");
		my $name   = $r->param("editname-new");
		PQS::model::categories::insert( $parent, $name);

	print STDERR "INSERT NEW $name\n";
	}


}


sub save_filters {
	my $r = shift;
	my $fid = $r->param('fid');

	if ( $r->param('name-new') ) {
		my $cat = $r->param("cat-new");
		my $name   = $r->param("name-new");
		PQS::model::product_filter::insert( $name, $cat);

	print STDERR "INSERT NEW $name\n";
	}


	map {  
		if ( $_=~ /option-(\d+)/ ) {
			my $name = $r->param($_);
			PQS::model::product_filter::insert_option( $name, $fid);
		}
	} $r->param();


}

sub builder { 
	my ($r, $dbh, $var) = @_;

	my $fid = $r->param('fid');

	if ( $r->param('Delete') ) {
	} elsif ( $r->param('Save')) {
		save_filters($r);
	}

	$var->{filters} = PQS::model::product_filter::get_all();
	$var->{parents} = ssi::make_drop_down(PQS::model::categories::select_list());
	$var->{fid} = $fid;

}


sub category_admin {
	my ($r, $dbh, $var) = @_;
	
print STDERR "START CATEGORY ADMIN \n";
	if ( $r->param('Delete') ) {
	} elsif ( $r->param('Save')) {
		save_categories($r);
	}




	my $start =  PQS::model::categories::get_children_from_id();
	my $list = _children($start, []);
	my $level;

	sub _children { 
		my $childs = shift;
		my $cat = shift;

		$level++;

		foreach my $id ( @{$childs}) {

			my $co   = PQS::model::categories::get($id);
			$co->{level} = $level;
			$var->{__FillInForm}{"parent-". $co->{id}} = $co->{parent};

			push @{$cat}, $co; 

			my $next = PQS::model::categories::get_children_from_id($id);

			_children( $next, $cat) if (@{$next} );
			
		}

		$level--;

		return $cat;

	}

	$var->{categories} = $list;

	$var->{parents} = ssi::make_drop_down(PQS::model::categories::select_list());
	

print STDERR "HAVE CATEGORIES: " , Dumper($list);
	return;


}

#List all products
sub list {
  my ($r, $dbh, $variable) = @_;


print STDERR "START PRODUCT LIST \n";
  update($r, $dbh, $variable) if $r->param('Save');

  PQS::model::products::remove($r->param('delete')) if $r->param('delete');
  
  importcsv($r, $dbh, $variable) if $r->upload("import");
  exportcsv($r, $dbh, $variable) if $r->param("export");
  
  price_import($r, $dbh, $variable) if $r->upload("price_import");
  price_export($r, $dbh, $variable) if $r->param("price_export");
  
  $variable->{products} = $dbh->selectall_arrayref("select * from tbl_products order by name", {Slice => {}});

  foreach my $p ( @{$variable->{products}} ) {
	foreach my $f (keys %{$p} ) {
		$p->{$f} = HTML::Entities::encode_entities($p->{$f});
	}
  }

  my $p = new PQS::Object::product;

  my @x = sort {$a->{sort_order} <=> $b->{sort_order} } @{$p->update_fields};

  $variable->{fields} = \@x;
  
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
			$p->set($f, $val);
		}

		$p->validate;
		$p->save;
	}


}


sub details {
	my ($r, $dbh, $var) = @_;
	 
	my $id = $r->param('id');
	my $p = new PQS::Object::product($id);
	$var->{product} = $p->specs();
	$var->{prices} = $p->prices();

	$var->{kit_list} = $p->kit_list();
 
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
 
 my $cat = $r->param('category');
 


  
  #Set categories for left nav.
  my $cats = PQS::model::categories::get_all();
  
  map { push @{$var->{categories}}, $cats->{$_}; } sort keys $cats;


  #Create category chain for parents of current category.
  my $parent = $cat;
  my $name =  PQS::model::categories::get_name_from_id($parent);    
  push @{$var->{cat_chain}}, { id => $parent, name => $name};

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


  #products of of current and all children cats.
  #
  $var->{products} =  PQS::model::categories::products_in_tree($cat);
  
  

  
  my $list = 1;
  my $cid = 1;
  foreach my $p (@{$var->{products}} ) {
    	$p->{category} = PQS::model::categories::get_name_from_id($p->{category});
	if ( $p->{kit} ) {
		my $kit = new PQS::Object::product($p->{id});
		$p->{price} = $kit->kit_price($cid);
	} else { 
    	$p->{price} = PQS::model::pricing::price_item($cid, $list, $p->{id}, 1);
	}

	my $img = "/images/main/products/$p->{strid}.jpg";
	my $path = ssi::get_file_path($r, $img);

	print STDERR "HAVE PATH: $path \n";

	$p->{image}  = -e $path ? $img : " /images/main/products/default.jpg";
  
  }



  
  

}


  
#Get details on a single product
sub get {
  my ($r, $dbh, $variable, $id) = @_;
  $id = $r->param('id') unless $id;
  return SERVER_ERROR unless $id;
  $variable->{product} = $dbh->selectall_arrayref("select * from tbl_products where id = ?", $id);
}


sub exportcsv {
  my ($r,  $dbh, $variable) = @_;
  
	my $list = PQS::model::products::list();

	my $h = new PQS::Object::product();
	my @data = [$h->import_fields];

	foreach my $product ( @{$list} ) {
		my $p = new PQS::Object::product($product->{id});

		push @data, $p->csv_export;
	
	}

	print STDERR "HAVE EXPORT DATA" , Dumper(\@data);
	my $log = session::log;
	misc::export_csv( $r, $variable, 'products.csv',  \@data );

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
	my ($r, $dbh, $variable) = @_;
	
	my @data  = [qw(strid min max cost sell)];

	my $pricelist = $r->param('pricelist');


	my $products = PQS::model::pricing::items($pricelist);


	foreach my $id (@{$products}) { 
		my $p = new PQS::Object::product($id);


		my $prices = $p->price_export($pricelist);


		map {	push @data,  

			[ $p->spec('strid'), $_->{min}, $_->{max}, $_->{cost}, $_->{sell} ]
			 
			 
		} @{$prices};

	}
	
	my $log = session::log;

	misc::export_csv( $r,  $variable, 'pricing.csv', \@data );


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
  
  while (my $row = $csv->getline($fh)) {
	
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
