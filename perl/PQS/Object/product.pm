package PQS::Object::product; 
use strict; 
use warnings; 
use session; 
use PQS::model::categories; 
use PQS::model::products;
use PQS::model::product_markup; 
use eprint::customer; 
use Data::Dumper;

my @import_fields = qw( strid category name description details part_number vendor minimum_qty 
				  	increment maximum_qty weight notes project active units lead_time delivery_days );

#my @import_fields = qw( strid category category name description details part_number vendor minimum_qty 
#				  	increment maximum_qty weight notes mediawide project active expiry product_group group_option units
#					tax_exempt3 lead_time );

my @update_fields =  (  
			{fname => 'strid', 			type => 'text', 	desc => 'Id', 				sort_order => 100},
			{fname => 'category', 		type => 'int', 		desc => '*Category', 		sort_order => 200},
			{fname => 'name', 			type => 'text', 	desc => '*Name', 			sort_order => 300, big=>1},
			{fname => 'description', 	type => 'text', 	desc => 'Description', 		sort_order => 400, big=>1},
			{fname => 'details', 		type => 'text', 	desc => '*Details', 		sort_order => 500, big=>1},
			{fname => 'part_number', 	type=> 'text', 		desc => 'Part #', 			sort_order => 600},
			{fname => 'vendor', 		type => 'int', 		desc => 'Vendor', 			sort_order => 700},
			{fname => 'minimum_qty', 	type => 'int', 		desc => '*Min', 			sort_order => 800},
			{fname => 'increment', 		type => 'int', 		desc => '*Increment', 		sort_order => 900},
			{fname => 'maximum_qty', 	type => 'int', 		desc => 'Max', 				sort_order => 1000},
			{fname => 'weight', 		type => 'num', 		desc => '*Weight', 			sort_order => 1100},
			{fname => 'notes', 			type => 'text', 	desc => 'Notes', 			sort_order => 1200},
#			{fname => 'mediawide', 		type => 'text', 	desc => 'Mediawide ID', 	sort_order => 1300},
			{fname => 'project', 		type => 'int', 		desc => 'Project', 			sort_order => 1400},
			{fname => 'active', 		type => 'bool', 	desc => '*Active',			sort_order => 0010},
			{fname => 'kit', 			type => 'bool', 	desc => 'Kit', 				sort_order => 0015},
#			{fname => 'expiry', 		type => 'date', 	desc => 'Expiry', 			sort_order => 1600},
#			{fname => 'product_group', 	type => 'text', 	desc => 'Product Group', 	sort_order => 1700},
#			{fname => 'group_option', 	type => 'text', 	desc => 'Prodctt Option', 	sort_order => 1800},
			{fname => 'units', 			type => 'text', 	desc => 'Units', 			sort_order => 1900},
#			{fname => 'tax_exempt3', 	type => 'bool', 	desc => 'County Tax Exempt', sort_order => 2000},
			{fname => 'lead_time', 		type => 'text', 	desc => 'Lead time', 		sort_order => 2100},
			{fname => 'delivery_days', 	type => 'int', 		desc => 'Delivery Days', 	sort_order => 2100},
			{fname => 'qprice', 	 	type => 'num', 		desc => 'Price', 			sort_order => 0001},
			);

sub new {
    my ($class,$id) = @_;
    
    my $self = { 
        log => session::log,
        dbh => session::dbh,
    };

    bless $self, $class;

    if ($id) {
        $self->{id} = $id;
        $self->load();
        $self->{list} = 1;
    }

    return $self;
}

sub prices {
  my $self 		= shift;
  my $cust_id 	= shift;
  my $qty 		= shift;
  

	my $markup = $self->markup($cust_id);
	my $price;

  	$price =  PQS::model::pricing::sell_prices( $self->{list}, $self->{id});
	map { 
		$_->{min} = 1   unless $_->{min};
		$_->{min} .= '+' unless $_->{max};
		$_->{sell} *=  1 + ( $markup / 100);
	} @{$price};


  
  die("Price not found: $self->{id}") unless $price;
  
  return $price;
}

sub version_discount {
  	my $self 		= shift;
	my $versions = shift;
 	
	return PQS::model::product_discount::get_discount($self->{id}, $versions);
}


sub price {
  my $self 		= shift;
  my $cust_id 	= shift;
  my $qty 		= shift;
  my $versions 	= shift;
  
  my $price;

	$price =  PQS::model::pricing::price_item($cust_id, $self->{list}, $self->{id}, $qty);


	print STDERR "Volumne DISCOUNT Price: $price / $qty \n";

	if ( $self->spec('kit') ) {
		$price =  $self->kit_price($cust_id) unless $price;
	}

	print STDERR "Kit  Price: $price \n";

	my $markup = $self->markup($cust_id);
	$price = $price * (1 + ( $markup / 100));

	print STDERR "Customer Discount Price: $price \n";

	if ( $self->{specs}{units} eq 'Per 1000' ) {
		$price /= 1000;
	}

	print STDERR "Per 1000 Adjustment Price: $price \n";

	my $version_discount = $self->version_discount($versions);

	print STDERR "PRICE BEFORE DISCOUNT: $price \n";

	$price -= ($version_discount / 100) * $price; 

	print STDERR "PRICE AFTER DISCOUNT: $price : $version_discount \n";

  
	#  die("Price not found: $self->{id}") unless $price;
  
  return $price;
}

sub markup {
	my $self 		= shift;
	my $cust_id 	= shift;
  	return PQS::model::product_markup::get($cust_id, $self->{specs}{category_id});

}

sub add_kit_item {
	my $self 	= shift;
	my $prod 	= shift;
	my $qty 	= shift;

#	PQS::model::products::remove_kit_item($self->{id}, $prod);
	PQS::model::products::add_kit_item($self->{id}, $prod, $qty);

}

sub remove_kit_category {
	my $self 	= shift;
	my $cat 	= shift;

	PQS::model::products::remove_kit_category($self->{id}, $cat);
}


sub kit_price {
	my $self 		= shift;
	my $cust_id		= shift;

	my $kit_price = 0;

	map {
		my $price = PQS::model::pricing::price_item($cust_id, $self->{list}, $_->{id}, $_->{qty});

		$kit_price += $price * $_->{qty};
print STDERR "Have price for $_->{id} QTY: $_->{qty} Price: $price \n";

		warn("Missing Price for Product: $_->{product} QTY: $_->{qty} ") unless $price;
 
	} @{$self->kit_list()};
	
	return $kit_price;



}

sub image {
	my $self = shift;
	my $small = shift;

	my $r = session::r;

	my $img;
	my $path;

	$img = "/images/main/products/$self->{specs}{strid}.jpg";

	 $path = ssi::get_file_path($r, $img);

	return $img if -e $path;

	$img = "/images/main/products/category/$self->{specs}{category_id}.jpg";

	$path = ssi::get_file_path($r, $img);


	return $img if -e $path;


	return "/images/main/products/default.jpg";
}

sub kit_list {
	my $self = shift;
	my $list =  PQS::model::products::kit_list($self->{id});
	map {
		my $p = new PQS::Object::product($_->{id});
		$_->{image} = $p->image;
	} @{$list};

	return $list;
}


sub weight {
	my $self = shift;
	my $qty  = shift;

	$qty = 1 unless $qty > 1;

	my $w = $self->get('weight');

	die("Missing Weight for PRODUCT: $self->{id} ") unless $w;

	return sprintf("%.2f", $w * $qty); 
	
}



sub load { 
  my $self = shift;
  
  $self->{id} = PQS::model::products::get_id_from_str($self->get('strid')) unless $self->{id};

  $self->{specs} = PQS::model::products::get($self->{id});
  
#  print STDERR "LOAD PRODUCT: $self->{id} HAVE PRODUCTS CAT: ", Dumper($self->{category_id}, $self->{specs} );
  
  
  $self->{specs}{category_id} = $self->{specs}{category};
  $self->{specs}{category}    = PQS::model::categories::get_name_from_id($self->get('category_id'));
  
}

sub add_option {
	my $self = shift;
	push @{$self->{options}}, shift;
}


sub import_fields {
	return @import_fields;
}

sub discount_export {
	my $self 		= shift;


	my $id = $self->{id};


	my $data = PQS::model::product_discount::array_for_item($self->{id});

	
	return $data;
}

sub price_export {
	my $self 		= shift;
	my $pricelist 	= shift;


	my $id = $self->{id};


	my $data = PQS::model::pricing::price_array_for_item($pricelist, $self->{id});

	
	return $data;
}

sub csv_export {
	my $self = shift;
	my $rec	 = shift;

	my $i = 0;

	my $line;
	my @data;
	map { push @data, $self->get($_) } @import_fields;
	
	return \@data;

}

sub csv_import {
	my $self   = shift;
	my $header = shift;
	my $rec	   = shift;

	my $i = 0;

	map { 

		my $val =  $rec->[$i];
print STDERR "SET FIELD: $_  = $val \n ";

		$self->set($_, $rec->[$i]);
		$i++;	
	} @{$header};
	#} @import_fields;

	my $cat_id = PQS::model::categories::get_id_from_name($self->{specs}{category});
	
	die("Cateeory mising: " . $self->{specs}{category} ) unless $cat_id;

	$self->{id} = PQS::model::products::get_id_from_str($self->get('strid') );
	
	$self->set('category_id', $cat_id);


}


sub set {
	my ($self, $spec,  $val) = @_;

	$self->{specs}{$spec} = $val;

}
sub update_fields {
	return [ sort {$a->{sort_order} <=> $b->{sort_order}} @update_fields];
}

sub field_list {

	my @list;
	map { push @list, $_->{fname} } @update_fields;
 	return @list;
}

sub save {
	my $self = shift;
	my $rec = shift;
	

print STDERR "HAVE PRODUCT ID: $self->{id} FOR $self->{specs}{strid} \n";
	$self->{id} = PQS::model::products::get_id_from_str($self->get('strid')) unless $self->{id};
	
	$self->{id} = PQS::model::products::insert( $self->get('strid') ) unless $self->{id};



	my @data;

	foreach my $f ( @update_fields )  { 
		my $field = $f->{fname};

		#next if $field eq 'category';
		if ($field eq 'qprice') {
			next;
		}
		
	  push @data, { name=> $field, value=> $self->get($field) } unless $field eq 'category'; 
	}

print STDERR "TIME TO SEND DATA TO UPDATE ", Dumper(\@data, $self->get('category_id'));


	PQS::model::products::update($self->{id}, \@data );


	PQS::model::products::update_category($self->{id}, $self->get('category_id'));


print STDERR "DELETE OPTIONS: $self->{id} \n";
	PQS::model::product_filter::delete_product_options($self->{id});


print STDERR "START SAVE ", Dumper($self->{specs});
	if ( $self->{specs}{qprice}  ) {

		my $qprice = $self->spec('qprice');
		
		my $pricelist = 1;

		PQS::model::pricing::clear_item($self->{id}, $pricelist);
		print STDERR "DELETE PRICE: $self->{id} \n";


		my $price = [1, $self->{id}, undef,  undef, 0, $qprice, undef, $pricelist];

		PQS::model::pricing::add_price(@{$price});

	}

	map {
		PQS::model::product_filter::insert_product_option($self->{id}, $_);
	}  @{$self->{options}};

#	PQS::model::products::update_category($self->{id}, $self->get('category_id'));
		
	


}

sub get {

	my $self = shift;
	my $spec = shift;

	return $self->{specs}{$spec};
}

sub specs {
  my $self = shift;
 return $self->{specs};
}

sub spec {
  my $self 	= shift;
  my $s 	= shift;

  die("Spec $s is for sure Invalid \n" .  Dumper($self->{specs})) unless exists $self->{specs}{$s};
  return $self->{specs}{$s};
}
	
	
  



sub record_error {
  my $red = shift;
}



sub validate {
  my $self = shift;
  my $row = shift;
print STDERR "TIME TO VALIDATE ******* \n", Dumper($self->{specs});

  map {
    
    my $f = $_;
    print STDERR "VALIDATE F: $f->{fname}  \n";
    if ( $f->{fname} eq 'project' ) {
      $self->set($f->{fname}, undef) unless $self->get($f->{fname});  
    } elsif ( $f->{fname} eq 'expiry' ) {
      $self->set($f->{fname}, undef) unless $self->get($f->{fname});  
    } elsif ($f->{type} eq 'int' ) {
      $self->set($f->{fname}, undef) if $self->get($f->{fname}) eq '';
    } elsif ($f->{type} eq 'num' ) {
      $self->set($f->{fname}, undef) if $self->get($f->{fname}) eq '';
    } elsif ($f->{type} eq 'bool' ) {
      $self->set($f->{fname}, 0) unless $self->get($f->{fname});
    }
    
  } @update_fields;

  return 1;
}
