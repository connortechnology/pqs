package PQS::Object::product; 
use strict; 
use warnings; 
use session; 
use PQS::model::categories; 
use PQS::model::products; 
use eprint::customer; 
use Data::Dumper;

my @import_fields = qw( strid category subcategory name description details part_number vendor minimum_qty 
				  	increment maximum_qty weight notes mediawide project active expiry product_group group_option units
					tax_exempt3 lead_time );

my @update_fields =  (  
			{fname => 'strid', 			type => 'text', 	desc => 'Id', 				sort_order => 100},
			{fname => 'category', 		type => 'int', 		desc => 'Category', 		sort_order => 200},
			{fname => 'name', 			type => 'text', 	desc => 'Name', 			sort_order => 300},
			{fname => 'description', 	type => 'text', 	desc => 'Description', 		sort_order => 400},
			{fname => 'details', 		type => 'text', 	desc => 'Details', 			sort_order => 500},
			{fname => 'part_number', 	type=> 'text', 		desc => 'Part #', 			sort_order => 600},
			{fname => 'vendor', 		type => 'int', 		desc => 'Vendor', 			sort_order => 700},
			{fname => 'minimum_qty', 	type => 'int', 		desc => 'Min', 				sort_order => 800},
			{fname => 'increment', 		type => 'int', 		desc => 'Increment', 		sort_order => 900},
			{fname => 'maximum_qty', 	type => 'int', 		desc => 'Max', 				sort_order => 1000},
			{fname => 'weight', 		type => 'num', 		desc => 'Weight', 			sort_order => 1100},
			{fname => 'notes', 			type => 'text', 	desc => 'Notes', 			sort_order => 1200},
			{fname => 'mediawide', 		type => 'text', 	desc => 'Mediawide ID', 	sort_order => 1300},
			{fname => 'project', 		type => 'int', 		desc => 'Project', 			sort_order => 1400},
			{fname => 'active', 		type => 'bool', 	desc => 'Active', 			sort_order => 1500},
			{fname => 'expiry', 		type => 'date', 	desc => 'Expiry', 			sort_order => 1600},
			{fname => 'product_group', 	type => 'text', 	desc => 'Product Group', 	sort_order => 1700},
			{fname => 'group_option', 	type => 'text', 	desc => 'Prodctt Option', 	sort_order => 1800},
			{fname => 'units', 			type => 'text', 	desc => 'Units', 			sort_order => 1900},
			{fname => 'tax_exempt3', 	type => 'bool', 	desc => 'County Tax Exempt', sort_order => 2000},
			{fname => 'lead_time', 		type => 'text', 	desc => 'Lead time', 		sort_order => 2100},
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

sub price {
  my $self 		= shift;
  my $cust_id 	= shift;
  my $qty 		= shift;
  
  my $price;

  if ( $self->spec('kit') ) {
  	$price =  $self->kit_price($cust_id);
  } else {
  	$price =  PQS::model::pricing::price_item($cust_id, $self->{list}, $self->{id}, $qty);
  }
  
  die("Price not found: $self->{id}") unless $price;
  
  return $price;
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

sub kit_list {
	my $self = shift;
	return PQS::model::products::kit_list($self->{id});
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
  
  $self->{specs} = PQS::model::products::get($self->{id});
  
  print STDERR "LOAD PRODUCT: $self->{id} HAVE PRODUCTS CAT: ", Dumper($self->{category_id}, $self->{specs} );
  
  
  $self->{specs}{category_id} = $self->{specs}{category};
  $self->{specs}{category}    = PQS::model::categories::get_name_from_id($self->get('category_id'));
  
}


sub csv_import {
	my $self = shift;
	my $rec	 = shift;

	my $i = 0;

	map { 
		$self->set($_, $rec->[$i]);
		$i++;	
	} @import_fields;

	my $cat_id = PQS::model::categories::get_id_from_name($self->{specs}{subcategory});
	
	die("Cateeory mising: " . $self->{specs}{subcategory} ) unless $cat_id;

	$self->{id} = PQS::model::products::get_id_from_str($self->get('strid') );
	
	$self->set('category_id', $cat_id);


}


sub set {
	my ($self, $spec,  $val) = @_;

	$self->{specs}{$spec} = $val;

}
sub update_fields {
	return \@update_fields;
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

	map { 
	  push @data, { name=> $_->{fname}, value=> $self->get($_->{fname}) } unless $_->{fname} eq 'category'; 
	} @update_fields;

print STDERR "TIME TO SEND DATA TO UPDATE ", Dumper(\@data);

	PQS::model::products::update($self->{id}, \@data );
	PQS::model::products::update_category($self->{id}, $self->get('category_id'));


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
  die("Spec $s is Invalid") unless defined $self->{specs}{$s};
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
