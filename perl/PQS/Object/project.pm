package PQS::Object::project; 

use strict; 
use warnings; 
use session; 

use Data::Dumper;


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

sub type_name {
	my $self = shift;

	my @t = eprint::project::get_type( $self->{log}, $self->{dbh}, $self->{id});
	return $t[1];
}

sub load {

}

sub ink_sum {
	my $self = shift;
	my $sid = shift;

	my $dbh = $self->{dbh};
	my $log = $self->{log};

# Side n colours and coatings.
        my @keys = qw(
            black        	    process
            drytrap      	    coating_type 
            varnish_spot_gloss  varnish_spot_matte
            varnish_flood       coating_texture
        );

        # Generate the full list of specs.
        my @specs;
        for my $side (qw(s0_ s1_)) {
            push @specs, "${side}${_}"          for @keys; # Colours/Coatings 
            push @specs, "${side}pms_${_}_name" for 1..8;  # PMS
        }

        my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
        );

        my (@count, @text);
        for my $s (0..1) {
            # Colours.
            $count[$s] = 0;
            $count[$s] += 4 if $results{"s${s}_process"};
            $count[$s] += 1 if $results{"s${s}_black"};

            for my $n (1..8) {
                $count[$s]++ if $results{"s${s}_pms_${n}_name"};
            }

            # Varnish
            $text[$s] .= ' +V' 
                if     $results{"s${s}_varnish_spot_gloss"} 
                    || $results{"s${s}_varnish_spot_matte"} 
                    || $results{"s${s}_varnish_flood"};

            # Coatings
            $text[$s] .= ' +' . uc(substr($results{"s${s}_coating_type"}, 0, 2))
                if $results{"s${s}_coating_type"};


		}

	my $sum = "$count[0]";

	$sum .= " / $count[1] " if $count[1];

	return $sum;

		

}

sub order_id {
	my $self = shift;
	return PQS::model::order::get_order_by_pid($self->{id});

}

sub sheet_count {

	my $self = shift;
	my $sid = shift;

	my $dbh = $self->{dbh};
	my $log = $self->{log};

	my @specs = qw( hdnGrossSheetCount1 );

	my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     );



	return $results{hdnGrossSheetCount1};


}
sub sheet_size {

	my $self = shift;
	my $sid = shift;

	my $dbh = $self->{dbh};
	my $log = $self->{log};

	my @specs = qw( hdnSuppliedStockWidth hdnSuppliedStockHeight );

	my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     );


	my $text = "$results{hdnSuppliedStockWidth} x $results{hdnSuppliedStockHeight} ";

	return $text;


}



sub stock_name {

	my $self = shift;
	my $sid = shift;

	my $dbh = $self->{dbh};
	my $log = $self->{log};

	my @specs = qw( stock_finish stock_colour stock_weight stock_name );

	my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     );

	 my $text = $results{stock_name};
	 $text .= " " . $results{stock_colour};
	 $text .= " " . $results{stock_finish};
	 $text .= " " . $results{stock_weight};


	return $text;


}



sub delivery_method {

	my $self = shift;
	my $pu = 'Pick-Up';

	my $dbh = $self->{dbh};
	my $log = $self->{log};

	my $sid =  eprint::project::check_for_service($log, $dbh, $self->{id}, 'Shipping');

	return $pu unless $sid; 

	my @specs = qw( deliverymethod ddmShipVia1 );
	
	my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     	);

	 my $ship;

	 if ( $results{deliverymethod} eq 'Standard' ) {

		 $ship = $dbh->selectrow_array(q{
			 SELECT strname FROM tbl_ship_via WHERE lngindex = ?
		 }, undef, $results{ddmShipVia1});
	 } else { 
		 $ship = $pu;
	 }




	return $ship;



}
sub due_date {
	
	my $self = shift;

	my $i = $self->order_id();

	my $date = PQS::model::order::duedate($self->{id});

	print STDERR "HAVE DUE DATE: $date \n";

	$date = $i->{dtmrequireddate} unless $date;


	$date =~ /(\d\d-\d*-\d*)/;

	#$date =~ s/\-//;

	return $1;

}

sub dims_finished {

	my $self = shift;
	my $sid = shift;

	my $dbh = $self->{dbh};
	my $log = $self->{log};

	my $sid = eprint::project::get_print_container($log, $dbh, $self->{id});


	my @specs = qw( final_width final_height );
    my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     );

	 my $text = "$results{final_width} x $results{final_height}";

	 return $text;

}




1;
