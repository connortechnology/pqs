package PQS::Object::project; 

use strict; 
use warnings; 
use session; 

use Data::Dumper;
use PQS::Object::order;
use PQS::model::project;
use Scalar::Util qw( looks_like_number );
use PQS::model::service;


require status;


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

sub type {
	my $self = shift;

	my @t = eprint::project::get_type( $self->{log}, $self->{dbh}, $self->{id});
	return $t[0];
}

sub load {
	
	my $self = shift;

 	$self->{specs} = PQS::model::project::get($self->{id});

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

sub upload_required {
	my $self = shift;
	my $val = shift;
	my $dbh = session::dbh;
	$dbh->do(q{
		update tbl_projects set upload_required = ?  where lngprojectindex = ?
	}, undef, $val, $self->{id});
	print STDERR "SET PROJECT: $self->{id} = $val \n";
}

sub no_service_dependencies {
	my $self = shift;
	my $dbh = session::dbh;
	my $log = session::log;

	my $pid = $self->{id};
	my $project_type = eprint::project::get_type($log, $dbh, $pid);

	return 1 if $project_type eq 'NoPrint';
	
	return 0;
}



sub no_upload_required {

	my $self = shift;
	my $dbh = session::dbh;



	my $nf = $dbh->selectrow_array(q{
		 select upload_required from tbl_projects where lngprojectindex = ?
	}, undef, $self->{id});

	print STDERR "SET PROJECT NE UPLOAD: $nf \n";

	return 1 if $nf eq '0';
	
}

sub have_production_file { 
	my $self = shift;
	my $dbh = session::dbh;

	my $file = $dbh->selectrow_array(q{
		 select count(*) from project_files where approval_production is not null AND pid = ?
	}, undef, $self->{id});

	return $file;
}

sub check_status {
	my $self = shift;


	my $oid = $self->order_id;
	my $order = new PQS::Object::order($oid);

	my $status  = '';
	if ( $oid ) {

		$status =  'WF';

		#If paymnet has not been made, do not allow order to go into production
		if ( $order->pending_deposit ) {
		   	$status =  'PD'
		} else { 

			$status =  'IP' if  $self->{specs}{files} && $self->have_production_file;
			$status =  'IP' if  $self->{specs}{strstatus} eq 'In Production';
			$status =  'IP' if  $self->no_upload_required;
		}




		$status = 'CN' if $order->{specs}{cancelled};
		$status =  'CP' if  $self->{specs}{completion_date};
	}

	if ( $status  eq 'IP' ) {
		$self->init_production unless ( $self->{specs}{init_production} );
	}

	return $status;

	
}

sub init_production {
	my $self = shift;
	my $s = $self->services;
	print STDERR "SERV: ", Dumper($s);
	my $dbh = session::dbh;

	foreach my $s ( @{$self->services} ) {
		#print STDERR Dumper($s);
		my $sid = $s->{lngserviceindex};
		my %specs = eprint::service::get_specifications_pairs(
				session::log, session::dbh, undef, $sid 
		);

		my $equip = $specs{hdnEquipment1} 
				 || $specs{txtEquipment} 
				 || $specs{DefaultEquipment} 
				 || $specs{equipment}
			 	 || 'ManualLabourStation-1';
		
		my $eid = looks_like_number($equip) ? $equip : PQS::model::service::get_index_from_id($equip);

		
		$self->set_equipment($sid, $eid);

		if ( $s->{strservicetype} eq 'Printing' ) {
				my $stock = $specs{hdnPaperIndex};
			    my $sheets = $specs{hdnPaperBuyQuantity1};
			    my $index =  $s->{lngserviceindex};
			print STDERR "INIT SET STOCK: $stock, $sheets, $index PD: $self->{id} \n";	
				if ( $stock && $sheets ) {
					$dbh->do(
						q{ Update tbl_project_contents SET stock = ?, gross_sheets = ? WHERE lngserviceindex = ? },
						undef, $stock, $sheets, $index
					);
					allocate_inventory($stock, $sheets);
				} else {
					# Data points not required for no print projects.
					if ( $self->type eq 'NoPrint' ) {
						print STDERR "HAVE NO PRINT Project \n";
					} else {
						die("MISSING DATA: STock $stock, Sheets, $sheets INDEX: $index PID: $self->{id} TYPE: "  . $self->type . " ");
					}

				}
	

		}
			

 
		print STDERR "HAVE EQUIPMENT: $equip, $eid FROM Service $s->{strservicetype} \n";


	}
}

sub allocate_inventory {
	my $stock = shift;
	my $sheets = shift;

	my $dbh = session::dbh;

	my $id = $dbh->selectrow_array(q{SELECT strid FROM tbl_paper WHERE lngindex = ?}, undef, $stock);

	$dbh->do(q{Update inventory_count SET onorder = onorder + ? WHERE id = ?}, undef, $sheets, $id);



}

sub services {
	my $self = shift;

	my $dbh  = session::dbh;
	my $sids = $dbh->selectall_arrayref(q{
		SELECT * FROM tbl_project_contents where lngprojectindex = ?}, { Slice => {} }, $self->{id});
	return $sids;

}

sub set_status {
	my $self = shift;
	my $status = shift;
	my $dbh  = session::dbh;
	my $log = session::log;

	PQS::model::project::set_status($self->{id}, $status);

	my $sids = $dbh->selectcol_arrayref(q{
		SELECT lngserviceindex FROM tbl_project_contents where lngprojectindex = ?}, undef, $self->{id});

	eprint::service::set_status($log, $dbh, $self->{id}, $status, @{$sids});


}

sub set_equipment {
	my $self = shift;

	my $sid = shift;
	my $value = shift;

	PQS::model::project::set_equipment($sid, $value);


}

sub update_status {
	my $self = shift;


	my $pid = $self->{id};

print STDERR "UPDATE PROJECT STATUS: $pid \n";

	my $oid = $self->order_id;


	if ( $oid ) {
		my $order = new PQS::Object::order($oid);


		my $status  = $self->check_status();

		PQS::model::project::set_status($pid, $status::project->{$status});

		$order->update_status() if $oid;

		$self->set_status($status::project->{$status});
	}



	return 	PQS::model::project::get_status($pid);

}


sub order {
	my $self = shift;
	return PQS::model::order::get_order_by_pid($self->{id});

}

sub quote_id {
	my $self = shift;
	my $dbh = session::dbh;
	my $qid = $dbh->selectrow_array(q{ 
			select lngquoteid from tbl_quote_details where lngprojectindex = ?
	}, undef, $self->{id});

	return $qid;
}

sub order_id {
	my $self = shift;
	return PQS::model::order::get_orderid_by_pid($self->{id});

}
sub parent_sheet_count {

	my $self = shift;
	my $sid = shift;

	my $dbh = $self->{dbh};
	my $log = $self->{log};

	my @specs = qw( hdnPaperBuyQuantity1 hdnGrossSheetCount1 txtSignatureQuantity );

	my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     );


	 my $count =  $results{hdnPaperBuyQuantity1} || $results{hdnGrossSheetCount1};

	 $count *= $results{txtSignatureQuantity} if  $results{txtSignatureQuantity} > 1;

	return $count;


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

	my @specs = qw( shipping_required ddmShipVia1 );
	
	my %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sid, @specs
     	);

	 my $ship;

	 if ( $results{shipping_required} ) {

		 $ship = $dbh->selectrow_array(q{
			 SELECT strname FROM tbl_ship_via WHERE lngindex = ?
		 }, undef, $results{ddmShipVia1}) || 'Shipping';
	 } else { 
		 $ship = $pu;
	 }




	return $ship;



}
sub date {

	my $self = shift;

	return $self->{specs}{dtmcreationdate};
}

sub due_date {
	
	my $self = shift;

	my $date = shift;

	if ( $date ) { 
		PQS::model::order::set_duedate($self->{id}, $date);
		return $date;
	}


	my $date = PQS::model::order::duedate($self->{id});

	
	my $i = $self->order();

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
