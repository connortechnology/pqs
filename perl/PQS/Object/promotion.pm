package PQS::Object::promotion; 

use strict; 
use warnings; 
use session; 

use Data::Dumper;
use PQS::Object::order;
use PQS::model::project;
use Scalar::Util qw( looks_like_number );
use PQS::model::service;
use PQS::model::promo;


require status;

my $self;

sub new {
    my ($class,$id) = @_;
    
    $self = { 
        log => session::log,
        dbh => session::dbh,
    };

    bless $self, $class;

    if ($id) {
        $self->{id} = $id;
        $self->load();
    }

    return $self;
}

sub load {

	my $specs = PQS::model::promo::get($self->{id});

	$specs->{startdate} =~  /(\d\d)-(\d\d)-(\d\d)/;
	$specs->{startdate} =  $2 && $3 ? "$2/$3/$1" : undef;

	$specs->{enddate} =~  /(\d\d)-(\d\d)-(\d\d)/;
	$specs->{enddate} = $2 && $3 ? "$2/$3/$1" : undef;

	$self->{specs} = $specs;




	$self->{specs}{marketing_categories} = PQS::model::promo::get_categories($self->{id});


}

sub id {
	unless ( $self->{id} ) {
		$self->{id} = PQS::model::promo::insert();
	}

	return $self->{id};
}


sub self_destruct {
	PQS::model::promo::delete($self->id);
}


sub formtodb {
	my $self = shift;

	my $param = shift;

	my $columns = PQS::model::promo::columns();

	my $data;

	#prevent null id field mapping for db update;
	$param->{id} = $self->id;



	map {

		$data->{$_} = $param->{$_};
		$self->{specs}{$_} = $param->{$_};

	} @{$columns};


	
	PQS::model::promo::update($self->id, $data);

	# UPDATE PROMO MARKETING CATEGORIES
	my $list = 	$param->{marketing_categories};
	$list = [$list] if ($list && ref $list ne 'ARRAY');

	PQS::model::promo::set_categories($self->id, $list);
	$self->{specs}{marketing_categories} = $list;

	print STDERR "HAVE PROMO SPECS: ", Dumper($param, $self->{specs});
}

sub check_date {
	my $list = shift;
	my @new_list;
	print STDERR "START CHECK DATE \n", Dumper($list);

	foreach my $p (@{$list} ) {

		my $active = PQS::model::promo::check_date($p);
		print STDERR "IS ACTIVE: $p, $active \n";
		push @new_list, $p if $active;
	}

	return @new_list;

}

sub discount {
	my $self = shift;
	my $price = shift;


	print STDERR "START DISCOUNT, USED: $self->{discountused}  \n";

	my $pd  =  $self->{specs}{percentdiscount};
	my $max =  $self->{specs}{maxdollar};

	my $disc = $price * ( $pd / 100 );
	
	if ( $self->{discountused} + $disc > $max ) {
		$disc = $max - $self->{discountused};
		$self->{discountused} = $max;

		print STDERR "HIT DOLLAR VALUE MAX: $max, $disc \n";
	} else {
		$self->{discountused} += $disc;
	}	

	print STDERR "CALC DISCOUNT ", Dumper($price, $disc, $self->{specs},$self->{discountused} );

	return $self->{discountused};
}

sub qualify {
	my $self = shift;
	my $pid = shift;
	my $prod = shift;

	my @list;
	print STDERR "START QUAL: $pid, $prod \n";

	if ( $prod ) {
		my $p = new PQS::Object::product($prod);
		my $cats = $p->cat_chain;

		print STDERR "HAVE CHAIN: ", Dumper($cats);

		foreach my $cat (@{$cats}) {
			my $promos = PQS::model::promo::promos_for_cat($cat->{id});

			print STDERR "FOUND PROMO For, $cat->{id} : ", Dumper($promos);

			push @list, @{$promos};
		}


	}

	@list = check_date(\@list);

	print STDERR "HAVE PROMO LIST", Dumper(@list), "\n";

	return @list;



}




1;
