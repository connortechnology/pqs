package eprint::Service::Shipping;
use strict;
use warnings;

use Date::Calc        qw(Delta_Days Today Add_Delta_Days Month_to_Text);

use eprint::Config;
use eprint::project  qw(get_weight get_print_container get_quantities);
use eprint::print_project qw(insert_service);
use eprint::service  qw(:common);
use eprint::customer ();
use sql              ();
use POSIX qw(ceil);
use POSIX qw(floor);
use jsrs;
use ssi ();

use PQS::model::order();

require eprint::address;


# These constants should really be equipment or configuration specs, but this
# is better than peppering the code with magic numbers.
use constant SAMPLE_NUMBER         => eprint::Config->get(Shipping => 'number_of_samples');
use constant MINIMUM_SHIP_WEIGHT   => eprint::Config->get(Shipping => 'min_ship_weight');       # lbs
use constant POUNDS_PER_PROOF_INCH => eprint::Config->get(Shipping => 'pounds_per_proof_inch'); # Based on 100lb text 

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

#	my $project_type = eprint::project::get_type($log, $dbh, $pid);
#	return 0 if $project_type eq 'InventoryCheckOut';
	
	my $u = $dbh->selectrow_array(q{
		SELECT lnguserindex FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

#	return 0 if $u ==2;
	
	#Make Shipping Not required for now.
#    return 0;
    return 1;
}

sub action {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;
print STDERR "ACTION: SHIPPING \n\n";

	if ( $specs->{rdbAdditional} eq 'Yes' ) {
		my $ship = insert_service( 
			$log, $dbh, $pid, 'Shipping', { user_requested => 1} 
		);
	    eprint::service::insert_service_specs( $log, $dbh, $pid, $ship,( 
        	txtServiceDescription => 'Project',
        	rdbShippingContents   => 'Project',
        	ShippingType          => 'Shipping_Project'
    	));
	}

	my $order_id = $dbh->selectrow_array(q{	
		SELECT max(lngorderid) FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $pid);
	my $quote_id = $dbh->selectrow_array(q{	
		SELECT max(lngquoteid) FROM tbl_quote_details WHERE lngprojectindex = ?
	}, undef, $pid);

	my ($cto, $ctq) = $dbh->selectrow_array(q{
		SELECT create_to_order, create_to_quote FROM tbl_projects where lngprojectindex = ?
	}, undef, $pid);

print STDERR "UPDATE STUFF: $order_id, $quote_id \n"; 

	if ( $cto && $order_id ) {
		update_order($dbh, $order_id, $specs);
	} elsif( $ctq && $quote_id ) {
		update_quote($dbh, $quote_id, $specs);
	}
}
sub update_quote {
	my ($dbh, $quote_id, $specs ) = @_;
	$dbh->do(q{ DELETE FROM tbl_Quote_Users_By WHERE lngQuoteID = ?}, undef, $quote_id);
	$dbh->do(q{ DELETE FROM tbl_Quote_Users_For WHERE lngQuoteID = ?}, undef, $quote_id);

	my @fields = qw( lngquoteid
		strcompanyname strfirstname strlastname straddress straddress2 strcity
		strstate strcountry strpostalcode 	strphone strext strfax stremail cubicle
	);

	my @data = (
		$quote_id,
		$specs->{txtCompanyName},
		$specs->{txtFirstName},
		$specs->{txtLastName},
		$specs->{txtAddress1},
		$specs->{txtAddress2},
		$specs->{txtCity},
		$specs->{ddmStateProvince},
		$specs->{ddmCountry},
		$specs->{txtPostalCode},
		$specs->{txtPhone},
		$specs->{txtExt},
		$specs->{txtFax},
		$specs->{txtEmail},
		$specs->{txtCubicle}
	);
	my $holders = join ',', ('?') x @data; 

	my $sql = 
		q{ INSERT INTO tbl_quote_users_by ( } . join(',',@fields) .  qq{ ) values ( $holders )};
	$dbh->do($sql ,undef, @data);

	$sql = 
		q{ INSERT INTO tbl_quote_users_for ( } . join(',',@fields) .  qq{ ) values ( $holders )};
	$dbh->do($sql ,undef, @data);


}

sub update_order {
	my ($dbh, $order_id, $specs ) = @_;
		$dbh->do(q{
			UPDATE tbl_orders SET 
				strponumber 	= ?,
				addorderinfo	= ?,
				strcompanyname 	= ?,
				strfirstname 	= ?,
				strlastname 	= ?,
				strtitle 		= ?,
				straddress1 	= ?,
				straddress2 	= ?,
				strcity  		= ?,
				strstate  		= ?,
				strcountry 		= ?,
				strpostalcode 	= ?,
				strphone 		= ?,
				strext 			= ?,
				strfax 			= ?, 
				stremail 		= ?,
				strCubicle 		= ?

			WHERE  lngorderid = ? 

		},undef, 
		$specs->{txtPurchaseOrder},
		$specs->{additionalOrderInformation},
		$specs->{txtCompanyName},
		$specs->{txtFirstName},
		$specs->{txtLastName},
		$specs->{rdbSalutation},
		$specs->{txtAddress1},
		$specs->{txtAddress2},
		$specs->{txtCity},
		$specs->{ddmStateProvince},
		$specs->{ddmCounty},
		$specs->{txtPostalCode},
		$specs->{txtPhone},
		$specs->{txtExtension},
		$specs->{txtFax},
		$specs->{txtEmail},
		$specs->{txtCubicle},
		,$order_id);
}

sub import_export {
	my ( $r, $log, $dbh, $var ) = @_;
	my $sid = $r->param('sid');
	my $pid = scalar $dbh->selectrow_array(q{
		SELECT lngprojectindex FROM tbl_project_contents WHERE lngserviceindex = ?
	},undef, $sid);

	if ( $r->param('Export') ) {
    my $header = [
				  'strcompanyname', 'strfirstname', 'strlastname',
                  'strsalutation', 'straddress1', 'straddress2', 'strcity',
                  'strstateprovince', 'strpostalcode', 'strcountry', 'strphone',
                  'strextension', 'strfax', 'stremail','add_qty1','add_qty2','add_qty3',
				  'cost_center', 'department', 'accountnumber', 'storemailinstructions'
	 ];



		my $sth = $dbh->prepare(q{
			SELECT lngindex,   
				  strcompanyname, strfirstname, strlastname,
                  strsalutation, straddress1, straddress2, strcity,
                  strstateprovince, strpostalcode, strcountry, strphone,
                  strextension, strfax, stremail
				FROM tbl_addresses WHERE lngindex IN ( 
				SELECT shipid FROM ship_address WHERE sid = ?)
		});

		$sth->execute($sid);
		my @data;
		while (my @row = $sth->fetchrow_array) {
			my $id = shift @row;
			my $specs = $dbh->selectall_hashref(qq{
				SELECT strname, strvalue FROM tbl_service_specifications
				WHERE lngserviceindex = ? 
				AND strname IN ( 
					'add_qty1-$id','add_qty2-$id','add_qty3-$id','cost_center-$id',
					'department-$id', 'accountnumber-$id', 'storemailinstructions-$id'
				)
			},'strname', {}, $sid );
			push @row, $specs->{"add_qty1-$id"}{strvalue};
			push @row, $specs->{"add_qty2-$id"}{strvalue};
			push @row, $specs->{"add_qty3-$id"}{strvalue};
			push @row, $specs->{"cost_center-$id"}{strvalue};
			push @row, $specs->{"department-$id"}{strvalue};
			push @row, $specs->{"accountnumber-$id"}{strvalue};
			push @row, $specs->{"storemailinstructions-$id"}{strvalue};
            push( @data, @row );

        }


		misc::export_csv(
            $r, $log, $var, 'shipping_address.csv', $header, \@data
        );
		
	}
	elsif ( $r->param('Import') ) {
		# Error out unless some sort of file has been uploaded.
		if (!defined $r->param('fileAddress') || $r->param('fileAddress') eq '') {
			 return misc::error(
				 $log, $dbh, $var, 'No file selected.', 
				 'You must select a file to import.'
			 );
		}
		

		# get the upload.
		my @content = misc::get_upload($r, $log, 'fileAddress');

		my @fields = map { tr/a-zA-Z0-9_//cd; lc $_ } split q{,}, shift @content;
		
		my @old_adds = $dbh->selectrow_array(q{
			SELECT shipid FROM ship_address WHERE sid = ?
		}, undef, $sid);

		map {
			$dbh->do(qq{DELETE FROM tbl_service_specifications 
						WHERE lngserviceindex = ? AND strname LIKE '%-$_' }, undef, $sid);
		} @old_adds;


		$dbh->do(qq{DELETE FROM ship_address WHERE sid = $sid});

		my $ins = $dbh->prepare(q{
			INSERT into tbl_service_specifications VAlues (?,?,?,?); 
		});
		my @keys = qw(add_qty1 add_qty2 add_qty3 cost_center department accountnumber storemailinstructions);

	
		my %data;
		map {
			$_ =~ s/\"//g;
		 	my ($id) = $dbh->selectrow_array(q{SELECT nextval('Address_Index_seq')});
			$data{lngindex} = $id;

			@data{@fields} = split q{,}, $_;
			foreach my $key (@keys) {
				$ins->execute($pid, $sid, "$key-$id", trim($data{$key}));
				delete $data{$key};
			}
print STDERR "HAVE INSERT DATA" ,Dumper(\%data);

			sql::insert($log, $dbh, 'tbl_addresses', %data);
			sql::insert($log, $dbh, 'ship_address', ( shipid => $id, sid => $sid ) );
			

		} @content;


	}

	$var->{sid} = $sid;

}
sub trim {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub insert_address {
	my ($log, $dbh,$sid, $specs) = @_;

	my $add = new eprint::address( $log, $dbh );
	my $index = $add->{index};

print STDERR "INSERT NEW ADDRESS SID: $sid I: - $index \n";


	$add->form_set($specs);
	$dbh->do(qq{
		INSERT INTO ship_address values ( $sid, $index )
	});

	update_shipnum($sid);

	my $fields = $add->form_fields();
	map { $specs->{$_} = undef } keys %{$fields};
	if ( $specs->{singlemultiple} eq '0' ) {
		$specs->{"add_qty1-$index"} = $specs->{hdnQuantity1};
		$specs->{"add_qty2-$index"} = $specs->{hdnQuantity2};
		$specs->{"add_qty3-$index"} = $specs->{hdnQuantity3};
	} else {
		$specs->{"add_qty1-$index"} = $specs->{add_qty1};
		$specs->{"add_qty2-$index"} = $specs->{add_qty2};
		$specs->{"add_qty3-$index"} = $specs->{add_qty3};
	}
	my $pid = $dbh->selectrow_array(q{
		SELECT lngprojectindex FROM tbl_project_contents WHERE lngserviceindex = ?
	}, undef, $sid);

	my $sth = $dbh->prepare(q{
		INSERT INTO tbl_service_specifications VALUES ( ?, ? ,?,?, true)
	});

#	$sth->execute($pid, $sid, "boxes-$index", 1);$specs->{cost_center};

#	$dbh->commit();

	#die();
	#
	#
	my $carton_sid 	= eprint::project::check_for_service( $log, $dbh, $pid, 'PlainCartons');

	my %cartons = $carton_sid 
				? eprint::service::get_specifications_pairs($log, $dbh, $pid, $carton_sid)
				: undef;

	my $qpb = $cartons{txtItemsPerPackage};
	my $ship_qty = $specs->{add_qty1};

	if ( $carton_sid ) {
		my $boxes  = $ship_qty % $qpb ? int($ship_qty / $qpb) + 1 : $ship_qty / $qpb;
		$boxes = 1 unless $boxes > 1;
		$specs->{"boxes-$index"} = $boxes;
		$specs->{"weight-$index"} =  sprintf("%.1f",$ship_qty * $cartons{hdnProjectWeight}),
	} else {
		$specs->{"boxes-$index"} = 1; 
		$specs->{"weight-$index"} =  1;
	}


#print STDERR "INSERT ($pid, $sid, boxes-$index, 1 \n";


	$specs->{"cost_center-$index"} 				= $specs->{cost_center};
	$specs->{"manualcostcenter-$index"} 		= $specs->{manualcostcenter};
	$specs->{"accountnumber-$index"} 			= $specs->{accountnumber};
	$specs->{"department-$index"} 				= $specs->{department};
	$specs->{"storemailinstructions-$index"} 	= $specs->{storemailinstructions};

#print STDERR "HAVE SPECS: ", Dumper($specs);

	return $index;
}

sub update_shipnum { 
	my $sid = shift;

	my $dbh = session::dbh;
	my $ids = $dbh->selectcol_arrayref(q{SELECT shipid FROM ship_address WHERE sid = ?}, undef, $sid);

	print STDERR "UPDATE SHIPNUM \n";

	map {
		my $num = $dbh->selectrow_array(q{	SELECT count(*) FROM ship_address WHERE sid = ? AND shipid <= ? }, undef, $sid, $_);
		$dbh->do(q{UPDATE ship_address SET shipnum = ? WHERE shipid = ?},undef,  $num, $_);
		print STDERR "UPDATE: $_ -- $num \n";
	} @{$ids};
	$dbh->commit;

}

sub fill_testing_specs {
    my ($var, $log, $dbh, $specs) = @_;

    my $lead_time = configuration::get_value($log, $dbh, "OrderLeadTime");

	# Use a default date of 15 days in future.
	@$specs{qw(ddmDueDateYear1 ddmDueDateMonth1  ddmDueDateDay1)} = Add_Delta_Days(Today(), $lead_time);

	#format with leading zeros on single digits to match ddm options in the html.
	$specs->{ddmDueDateMonth1} = sprintf("%02d",  $specs->{ddmDueDateMonth1});
	$specs->{ddmDueDateDay1}   = sprintf("%02d",  $specs->{ddmDueDateDay1});

	#Default timee of 5:00 pm
	$specs->{ddmDueDateTime} = "5:00 pm";

	return;
}



sub preaction {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;
	use Data::Dumper;

	my $r = session::r;
	my $cid = $dbh->selectrow_array(q{SELECT lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?}, undef, $pid);


	my $cust = new eprint::obj_customer( $log, $dbh, $cid);

	if ( $specs->{'New Address'} ) {
		if ( $specs->{Save_Ship_Address} ) {

			$cust->save_shipping( 'New', $specs, 1 );

		} else {

			print STDERR " NO Save Address \n", Dumper($specs);

		}

		if ( $specs->{contact_default} ) {
			my @fields = qw{txtAddress1 txtAddress2 txtCity ddmStateProvince txtPostalCode ddmCountry txtPhone txtExtension txtFax};
			
			foreach my $f ( @fields )  {

				my $val = $specs->{$f};
				next unless $val;

				$f =~ s/ddmStateProvince/strprovstate/;
				$f =~ s/ddmCountry/strcountry/;
				$f =~ s/txtPostalCode/strpostalcodezip/;
				$f =~ s/txtExtension/strext/;
				$f =~ s/txt/str/;

				$dbh->do(qq{UPDATE tbl_customer SET $f = ? WHERE lngcustomerid = ?}, undef, $val, $cid);
			}
		}

		insert_address($log, $dbh, $sid, $specs);

	}
	elsif ( $specs->{'Delete Address'} ) {

		$specs->{delete} = [$specs->{delete}] 
			unless ref($specs->{delete}) eq 'ARRAY';

		map {
			my $add = new eprint::address( $log, $dbh, $_ );
			$add->delete();
		} @{$specs->{delete}};

	} elsif ($specs->{ddmShippingCompany} && $specs->{btnFunction} eq 'Get Address' ) {

		my $add = new eprint::address( $log, $dbh, $specs->{ddmShippingCompany} );
		$add->bake_form_hash($specs);
		delete $specs->{btnFunction};

	}

	update_shipnum($sid);

	$specs->{Location} = '';
}



sub calc {

    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs) = @_;
print STDERR "CALC MY SHIPPING SERVICE \n\n";


	my $shipids = $dbh->selectcol_arrayref(q{
		SELECT shipid FROM ship_address WHERE sid = ?
	}, undef, $sid);

	if (    $specs->{singlemultiple} eq '0' 
  		 && $specs->{txtShippingContact} 
	) {

		#	map { my $add = new eprint::address( $log, $dbh, $_);
		#	     $add->delete();
		#} @{$shipids};

		#	my $i = insert_address( $log, $dbh, $sid, $specs);
		#  $shipids = [ $i ];
	}

	my $status;

	$status = 'calculated' if $specs->{deliverymethod} eq 'Customer Pick-up';
	my $totals = [0.0.0,0];
	my @qty = ( undef,
				$$specs{txtQuantity1},
				$$specs{txtQuantity2},
				$$specs{txtQuantity3});

	foreach my $shipid (@{$shipids}) {
		
		map { $$specs{"txtQuantity$_"} = $$specs{"add_qty${_}-$shipid"} } (1..3);

		#return 'uncalculated' unless $specs->{txtQuantity1};

    	$status = calc_price($log, $dbh, $variable, $pid, $sid, 
							 	   $service_type, $specs, $shipid);
		my $no_price;
		$no_price = 1 if $specs->{deliverymethod} eq 'Duplicating Center Hand Delivery';
		$no_price = 1 if $specs->{deliverymethod} eq 'Interoffice Mail';
		$no_price = 1 if $specs->{deliverymethod} eq 'Store Mail - Norcal';
		$no_price = 1 if $specs->{deliverymethod} eq 'Store Mail - Norcal+Hawaii';
		$no_price = 1 if $specs->{deliverymethod} eq 'Store Mail - All Stores';

		if ( $no_price ) {
    		map { $$specs{"txtPrice$_"} = '0.00' } ( 1..3);
			$status = 'calculated';
		} else {
    		$status = calc_price($log, $dbh, $variable, $pid, $sid, 
							 	   $service_type, $specs, $shipid);
		}

    	map { $$specs{"add_price${_}-$shipid"} = $$specs{"txtPrice$_"} } ( 1..3);

		map { $$totals[$_] += $$specs{"txtPrice$_"} } (1..3);
		
	}

	#map { $$specs{"txtQuantity$_"} = $qty[$_] } (1..3);
	#map { $$specs{"txtPrice$_"}    = $$totals[$_] } (1..3);

	map { $$specs{"txtQuantity$_"} = $qty[$_] } (1..3);

	map { $$specs{"txtPrice$_"}    = $$totals[$_] } (1..3);
	

	# Remove Address data inserted by calc price.
	my $add = eprint::address->new($log, $dbh);
	map { delete $specs->{$_} } keys %{$add->form_fields};

	#override all errors for now.
	$status = 'calculated';
	$status = 'uncalculated' unless $specs->{deliverymethod};

	print STDERR "HAVE STATUS: $status - $specs->{deliverymethod}  \n";
	return $status eq 'calculated' ? $status : 'uncalculated';
}


sub calc_price {
    my ($log, $dbh, $variable, $pid, $sid, $service_type, $specs, $shipid) = @_;

	my $add = eprint::address->new($log, $dbh, $shipid);

	$add->bake_form_hash($specs);

    for my $i (1..3) {

        next if $specs->{"ddmShipVia$i"};

        my $type = $specs->{rdbShippingContents};
        my $ship_method = configuration::get_value($log, $dbh, "${type}ShippingOverride");

        if ( ! $ship_method ) {
            $ship_method = configuration::get_value($log, $dbh, 'DefaultShipMethod');
            ($specs->{"ddmShipVia$i"}) = sql::sql_statement($log, $dbh, qq{
                SELECT lngIndex FROM tbl_Ship_Via WHERE strID = '$ship_method'
            });
        } else {
            $specs->{"ddmShipVia$i"} = $ship_method;
        }
    }

#print STDERR "\n 1. SHIPPING COUNTRY: $specs->{ddmShippingCountry} \n\n";

    # specs must include destination postal code, province and country and
    # ShipVia index to get ship info.
    @$specs{qw( FPCode  FProv  FCountry 
                TPCode  TProv  TCounrtry  
                PriceList )} = get_ship_locations($log, $dbh, $pid, $specs);

    my @bestmethod;
    my $status     = 'calculated';
    my $price_list = $$specs{'PriceList'};

    my $weight =
      $$specs{'txtProjectWeight'};   # this is the weight of one finished piece.

    # txtShipmentWeight is displayed on shipping page
    my $ship_weight_in = $$specs{"txtShipmentWeight"};
    my $ship_contents = $$specs{'rdbShippingContents'}; 

    # we want to shove in our weights whenever we calc at all, so that the ssi
    # and use these dynamically on the radio button
    $$specs{'hdnSampleQuantity'} = SAMPLE_NUMBER;

    $_ = qq{
			select SUM(cast (strvalue as numeric)) 
	   		from tbl_service_specifications 
	   		where lngprojectindex='$pid' and strname like '%txtProofQuantity%'
	};
    my ($total_proof_quantity) = sql::sql_statement($log, $dbh, $_);
    $$specs{'hdnProofQuantity'} = $total_proof_quantity;

    if ($weight == 0) {

        $_ =
          "SELECT dblProjectWeight FROM tbl_Inventory WHERE lngInventoryIndex= "
          . " ( SELECT strValue::INT4 FROM tbl_Service_Specifications WHERE lngProjectIndex='$pid' AND strName='InventoryIndex')";
        ($weight) = sql::sql_statement($log, $dbh, $_);
    }
    my $project_type = scalar $dbh->selectrow_array(
        q{
        SELECT strid
        FROM tbl_projecttypes
        WHERE lngindex = (
            SELECT lngprojecttype
            FROM tbl_projects
            WHERE lngprojectindex = ?
        )
    }, undef, $pid);

	if ( $project_type eq 'NoPrint' ) {
		$ship_contents = 'Product';
		
	}

    $_ =
      "select strvalue from tbl_service_specifications where strname='OriginalProjectIndex' and lngprojectindex='$pid'";
    my ($original_index) = sql::sql_statement($log, $dbh, $_);
    $weight = get_weight($log, $dbh, $original_index) if $original_index;
    $weight = get_weight($log, $dbh, $pid, $ship_contents) if $weight == 0;
    my $screen_weight;
    my $printing_service = get_print_container($log, $dbh, $pid);

    my @qtys       = (undef, get_quantities($log, $dbh, $pid));
    if ($project_type eq 'ScreenItem') {
        $screen_weight = scalar $dbh->selectrow_array(
            q{
            SELECT strvalue
            FROM tbl_service_specifications
            WHERE strname = 'txtScreenPrintingItemWeight'
              AND lngserviceindex = ?
         }, undef, $printing_service);
    }
    $$specs{"txtShipmentWeight"} = '';
    # for now proofs are going to be a standard 5 pounds.
    my @weights = split(',', $ship_weight_in);
	my $price_over;

print STDERR "SHIPPING CALC 1. \n";

    for (my $index = 1; $index <= 3; $index += 1) {
        my $bestprice = 0;
        $bestmethod[$index - 1] = 0;
        my $price = 0;
        my ($name_quantity, $original_quantity) =
          eprint::service::get_specifications($log, $dbh, $pid,
                     $printing_service, 'txtNameQuantity', "txtQuantity$index");
        $name_quantity = 1 if !$name_quantity;


        my $qty = $$specs{"txtQuantity$index"};

        $qty = $name_quantity * $original_quantity unless $qty;

        $$specs{"txtQuantity$index"} = $qty;

print STDERR "SHIPPING CALC I: $index Q: $qty \n";

        if ($qty) {
            my $ship_weight = 0;
		  	if ( $specs->{chkWeightOverride} ) {
          		$ship_weight = $weights[$index-1] ? $weights[$index-1] : $weights[0];
			}
            elsif ($ship_contents eq 'Proofs') {

                # for now proofs are going to be a standard 5 pounds.
                #$ship_weight = 5;
                $_ =
                  "select SUM(cast (strvalue as numeric)) from tbl_service_specifications where lngprojectindex='$pid' and strname like '%txtProofArea%'";
                my ($total_proof_area) = sql::sql_statement($log, $dbh, $_);
                $ship_weight = POUNDS_PER_PROOF_INCH * $total_proof_area;
#                $log->debug(
#                    "SHIPPING, PROOFS: total proof area: $total_proof_area square inches ... total weight: $ship_weight"
#                );
                $ship_weight = MINIMUM_SHIP_WEIGHT
                  if $ship_weight < MINIMUM_SHIP_WEIGHT;
            }
            elsif ($ship_contents eq 'Other') {

                if ($project_type ne 'ScreenItem') {
                    $ship_weight = $weight * SAMPLE_NUMBER;
                    #$log->debug("SHIPPING: samples weigh: $ship_weight");
                }
                else {
                    $ship_weight = $screen_weight * SAMPLE_NUMBER;
#                    $log->debug(
#                        "SHIPPING, SCREEN: screen item samples weigh: $ship_weight"
#                    );
                }
                $ship_weight = MINIMUM_SHIP_WEIGHT
                  if $ship_weight < MINIMUM_SHIP_WEIGHT;
            }
            else {
                if ($project_type ne 'ScreenItem') {
                    $ship_weight = $weight * $qty;
                }
                else {
                    $ship_weight = $screen_weight * $qty;
                }
                $ship_weight = ceil($ship_weight);
                $ship_weight = MINIMUM_SHIP_WEIGHT
                  if $ship_weight < MINIMUM_SHIP_WEIGHT;
            }


print STDERR "SHIPPING CALC: W: $ship_weight Q: $qty \n ";

            my @methods;
            if ($$specs{ 'chkOverrideShipper' . $index } eq 'Y') {
                @methods = $$specs{ 'ddmShipVia' . $index };
            } else {
                @methods =
                  sql::sql_statement($log, $dbh,
                                  "select distinct lngindex from tbl_ship_via");
            }

            foreach my $ship_method (@methods) {
                my ($f_zone, $t_zone) =
                  get_ship_zones($log, $dbh,
                                 $ship_method,
                                 @$specs{
                                     'FPCode',   'FProv',
                                     'FCountry', 'TPCode',
                                     'TProv',    'TCounrtry', 'deliverymethod'
                                   });
#	print STDERR "SHIP ZONES: $f_zone to $t_zone \n";
                my $sth =
                  $dbh->prepare(
                    "select lngmin, lngmax, strunits,dblcost,dblmarkup from tbl_shipping_prices where lngshipviaindex=? and lnglistindex=? and strfromzone = ? and strtozone=? ORDER BY lngMax"
                  );

                $sth->execute($ship_method, $price_list, $f_zone, $t_zone);
                while (my ($min, $max, $units, $cost, $markup) =
                       $sth->fetchrow_array)
                {
                    if ($units eq 'base') {
                        $price =
                          $cost * (1 + ($markup / 100))
                          ;    # we are flat or inside the base rate
#                        $log->debug(
#                            "SHIPPING: units are: $units ... generating price of: $price ... for method: $ship_method"
#                        );
                    }
		    elsif ($units eq 'flat' ) {
		    	if ( $ship_weight >= $min && ($ship_weight < $max || !$max) ) {
                        	$price = $cost * (1 + ($markup / 100)) ;
#                        $log->debug(
#                            "SHIPPING: units are: $units ... generating price of: $price ... for method: $ship_method"
#                        );
				}
            }
                    else {     # we are in per pound pricing
                        my $unit_weight = 0;
                        if ($ship_weight > $max and $max) {
                            $unit_weight = $max - $min;
                        }
                        elsif ($ship_weight >= $min) {
                            $unit_weight = $ship_weight - $min;
                        }
                        $price += $cost * $unit_weight * (1 + ($markup / 100));
#                        $log->debug(
#                            "SHIPPING: units are: $units ... generating price of: $price ... for method: $ship_method UW: $unit_weight"
#                        );
                    }
                }
                if ($price < $bestprice || !$bestprice) {
                    $bestprice = $price;
                    $bestmethod[$index - 1] = $ship_method;
                }
            }
            $price = $bestprice;

			my $cust_price = $$specs{ 'txtCustomSkidPrice' . $index };

            if (int($cust_price) > 1 || $cust_price eq '0' || $cust_price eq '0.00')
            { # override price after calculation - this way we know we're getting the right kind of shipping still
                 # administrator as inserted a custom price on the shipping page.
                $price = $$specs{ 'txtCustomSkidPrice' . $index };
                $log->debug(
                       "SHIPPING: overriding price #: $index to equal: $price");
				$price_over = 1;
            }


#            $$specs{"txtPrice$index"} = sprintf('%.2f', floor($price));
            $$specs{"txtPrice$index"} = sprintf('%.2f', $price);
            $$specs{"txtShipmentWeight"} .= $$specs{"txtShipmentWeight"} ne '' 
												? ',' . $ship_weight 
												: $ship_weight;
        }
    }
    if (    $$specs{'txtPrice1'} == 0
        and $$specs{'txtPrice2'} == 0
        and $$specs{'txtPrice3'} == 0
		and ! $price_over
	) {
        $status = 'uncalculated';
    }

    $$specs{'ddmShipVia1'} = $bestmethod[0];    # displayed on page
    $$specs{'ddmShipVia2'} = $bestmethod[1];    # displayed on page
    $$specs{'ddmShipVia3'} = $bestmethod[2];    # displayed on page
    $log->debug("SHIPPING: setting bestmethod to: @bestmethod");
    my $shipviaquery = "select strname from tbl_ship_via where lngindex = ?";
    $$specs{'hdnShipVia1'} =
      scalar $dbh->selectrow_array($shipviaquery, undef, $bestmethod[0]);
    $$specs{'hdnShipVia2'} =
      scalar $dbh->selectrow_array($shipviaquery, undef, $bestmethod[1]);
    $$specs{'hdnShipVia3'} =
      scalar $dbh->selectrow_array($shipviaquery, undef, $bestmethod[2]);

    #    $$specs{"txtPrice$index"}             # displayed on page
    #    $$specs{"txtShipmentWeight"}        # displayed on page
    return $status;

}

sub price_service {

	my ($weight, $ship_method, $price_list, $f_zone, $t_zone) = @_;
	my $dbh = session::dbh;

	print STDERR "PRICE SERVCIE:  ", Dumper(@_);


	my $price;

	my $sth = $dbh->prepare(q{
		select lngmin, lngmax, strunits,dblcost,dblmarkup from tbl_shipping_prices 
			where lngshipviaindex=? and lnglistindex=? and strfromzone = ? and strtozone=? ORDER BY lngMax
	});

	$sth->execute($ship_method, $price_list, $f_zone, $t_zone);
	while (my ($min, $max, $units, $cost, $markup) = $sth->fetchrow_array)
	{
		if ($units eq 'base') {
			$price =
			  $cost * (1 + ($markup / 100))
		}
		elsif ($units eq 'flat' ) {
			if ( $weight >= $min && ($weight <= $max || !$max) ) {
				$price = $cost * (1 + ($markup / 100)) ;
			}
		}
		else {     # we are in per pound pricing
			my $unit_weight = 0;
			if ($weight > $max and $max) {
				$unit_weight = $max - $min;
			}
			elsif ($weight >= $min) {
				$unit_weight = $weight - $min;
			}
			$price += $cost * $unit_weight * (1 + ($markup / 100));
		}
	}
	return $price;
}

sub product_weight {
	my $order_id = shift;
	my $products = PQS::model::order::get_products($order_id);
	
	my $total_weight;


	foreach my $prod (@{$products}) {
		my $p = new PQS::Object::product($prod->{product});

print STDERR "HAVE PRODUCTS: ", Dumper($prod);

		my $qty = $prod->{intquantity};
		
		die("Order missing Quantity for Product: $prod->{product} \n") unless $qty;

		$total_weight += $p->weight($qty);
	

	}

print STDERR "ORDER: $order_id HAS WEIGHT: $total_weight \n";
	return $total_weight;
}

sub order_ship_cost {
	my $order_id 	= shift;
	my $ship_method = shift;

	my $dbh = session::dbh;
	my $log = session::dbh;

	my $price_list  = 1;


	my $weight = product_weight($order_id);

	unless ($weight) {
		print STDERR "THIS ORDER HAS NO PRODUCT WEIGHT: $order_id \n";
		return 0;
	}

	my @add = PQS::model::order::address($order_id);

	my @specs = (undef, undef, undef, @add,, undef); 
print STDERR "SHIP: Method: $ship_method ORDER: $order_id WEIGHT: $weight \n";

print STDERR "GET ADDRESS: @add \n";

    my ($f_zone, $t_zone) = get_ship_zones($log, $dbh, $ship_method, @specs);

print STDERR "HAVE ZONES: $f_zone, $t_zone \n";

	print STDERR "HAVE SHIP WEIGHT: $weight \n";

	my $price = price_service($weight, $ship_method, $price_list, $f_zone, $t_zone);

print STDERR "HAVE PRICE: $price \n";
	return $price;


}


# Returns Shipping To/From Zones and Customer Pricelist index.
# $specs must include destination postal code, province, country and ShipVia index.
sub get_ship_locations {
    my ($log, $dbh, $pid, $specs) = @_;
#print STDERR "\n SHIPPING COUNTRY $specs->{ddmShippingCountry} \n\n";
    my $to_country = $specs->{ddmShippingCountry};
    my $to_prov    = $specs->{ddmShippingStateProvince};
    my $to_postal  = $specs->{txtShippingPostalCode};

    # ***** Get From Address ******
    # for now we are going to use the printer as shipping From location.
    my $press = $dbh->selectrow_array(q{
        SELECT strValue 
        FROM tbl_Service_Specifications 
        WHERE strName = 'hdnPress'
          AND lngProjectIndex = ?
    }, undef, $pid);

    $_ = "SELECT strSupplier FROM tbl_Equipment WHERE strId='$press'";
    my ($supplier) = sql::sql_statement($log, $dbh, $_);
    
    $_ =
      "SELECT strPostalCodeZip, strProvState, strCountry FROM tbl_Customer where strCompanyName='$supplier'";
    my ($from_postal, $from_prov, $from_country) =
      sql::sql_statement($log, $dbh, $_);

    $_ =
      "SELECT lngPriceList FROM tbl_Customer, tbl_Projects where tbl_Projects.lngCustomerID = tbl_Customer.lngCustomerId AND lngProjectIndex='$pid'";
    my ($price_list) = sql::sql_statement($log, $dbh, $_);

    
    my @data = ($from_postal, $from_prov, $from_country, $to_postal, $to_prov,
      $to_country, $price_list);
	return @data;
}

sub get_ship_zones {
    my $log         = shift;
    my $dbh         = shift;
    my $ship_method = shift;
    my $f_pcode     = shift;
    my $f_prov      = shift;
    my $f_country   = shift;
    my $t_pcode     = shift;
    my $t_prov      = shift;
    my $t_country   = shift;
    my $deliverymethod = shift;

    my $f_zone =
      lookup_zone_id($log, $dbh, $f_pcode, $f_prov, $f_country, $ship_method);
    if ($f_zone eq '') {
        $f_zone = configuration::get_value($log, $dbh, 'DefaultShipFromZone');
    }
    my $t_zone =
      lookup_zone_id($log, $dbh, $t_pcode, $t_prov, $t_country, $ship_method);

    $t_zone = $f_zone if $deliverymethod eq 'Customer Pick-up';

    return $f_zone, $t_zone;
}


# Given a country, province, postal code and carrier (only one of postal code
# or province is strictly required) determine that carrier's shipping zone.
sub lookup_zone_id {
    my ($log, $dbh, $postal, $prov, $country, $carrier) = @_;

    # TODO: Rework the order of the arguements and get some real assertions
    # either in here or better yet where the data comes in.

	$postal  = '' unless $postal;
	$prov 	 = '' unless $prov;
	$country = '' unless $country;



    $postal  =~ tr/A-Za-z0-9//cd if $postal;    # Only allow alpha-numeric
    $prov    =~ tr/A-Za-z //cd   if $prov;      # Only allow alpha and space
    $country =~ tr/A-Za-z//cd    if $country;       # Only allow alpha (2 digit code)

    warn "Invalid postal/zip code ($postal) for country ($country)."
      if ($country eq 'CA' and $postal !~ /^[A-Z]\d[A-Z]\d[A-Z]\d$/i)
      or ($country eq 'US' and $postal !~ /^\d{5}(?:\d{4})?$/);

    # Most of the CA Zone lookup ranges only specify the first 3 char of a
    # postal code, so if the the start range and the end range are the same
    # 'L4H' to 'L4H' then looking up 'L4H 1A1' will not fall between 'L4H' and
    # 'L4H'. To work around this for now wil will only use 3 characters for
    # looking up postal codes.

    $postal = substr($postal, 0, 3) if $country eq 'CA';
#print STDERR "POSTAL: $postal COUNTRY: $country \n";

    # Our default lookup is by postal code if one exists.
    my $zone = $dbh->selectrow_array(
        q{
        SELECT l.strid 
        FROM tbl_zone_lookup l, tbl_shipping_zones z
        WHERE l.strid = z.strid
          AND l.lngshipviaindex = ?
          AND z.strcountry      = ?
          AND lower(?::text) BETWEEN lower(l.strstartrange) AND lower(l.strendrange)
    }, undef, $carrier, $country, $postal
    ) if $postal;

    # If we didn't get any results from the postal/zip code lookup we'll fall
    # back to an older lookup style using only the state/province.
    if ((not $zone) and $prov) {
        $zone = $dbh->selectrow_array(
            q{
            SELECT l.strid 
            FROM tbl_zone_lookup l, tbl_shipping_zones z
            WHERE l.strid = z.strid
              AND z.lngshipviaindex = ?
              AND z.strcountry      = ?
              AND l.strstartrange   = ?
        }, undef, $carrier, $country, $prov);
    }

    return $zone; # This may be undefined.
}


# TODO: This is a function stub, it's not complete.
#
# Return the carriers that can ship from and to the specified locations; they
# must also have pricing for the given price list.
sub valid_carriers {
    warn "valid_carriers() was called. I'm an incomplete function stub.";
    return undef;


    my $log  = shift;
    my $dbh  = shift;
    my $list = shift;    # Customer's price list.
    my $from = shift;    # Zone we're shipping from.
    my $to   = shift;    # Zone we're shipping to.
    my %carriers;        # Carriers that can ship between the two areas.

    my $sth = $dbh->prepare(
        q{
        SELECT DISTINCT lngindex AS id, strname AS name
        FROM tbl_ship_via
        WHERE 
          AND p.strfromzone = ?
          AND p.strtozone   = ?
    });

    return %carriers;
}

sub display {
    my ($log, $dbh, $service_type, $pid, $sid, $specs, $variable) = @_;

	#This function was missing $specs in line above.
	#was using variable in place of specs.
	map { $variable->{$_} = $specs->{$_} } keys %{$specs};


	fill_testing_specs($variable, $log, $dbh, $specs) unless $specs->{ddmDueDateMont1};


    $_ = "SELECT lngIndex, strName FROM tbl_Ship_Via";
    $$variable{'SHIP_OPTIONS'} = ssi::fill_drop_down($log, $dbh, $_);

	my $sql = qq{
		SELECT lngindex, shipname FROM tbl_addresses WHERE lngindex IN (
			SELECT shipid FROM customer_ship_address, tbl_projects 
			WHERE customer_ship_address.customer = tbl_projects.lngcustomerid 
			AND lngprojectindex = $pid )
	};
    $$variable{'Ship_Addresses'} = ssi::fill_drop_down($log, $dbh, $sql);

    # we want to shove in our weights whenever we calc at all, so that the ssi
    # and use these dynamically on the radio button
    $variable->{'hdnSampleQuantity'} = SAMPLE_NUMBER;

    $_ = qq{
			select SUM(cast (strvalue as numeric)) 
	   		from tbl_service_specifications 
	   		where lngprojectindex='$pid' and strname like '%txtProofQuantity%'
	};
    my ($total_proof_quantity) = sql::sql_statement($log, $dbh, $_);
    $variable->{'hdnProofQuantity'} = $total_proof_quantity;

    my @qty       = (undef, get_quantities($log, $dbh, $pid));

    for my $i (1..3) {
		my $q = $variable->{txtServiceDescription} eq 'Samples' ?  $variable->{hdnSampleQuantity}
			  : $variable->{txtServiceDescription} eq 'Proofs'  ?  $variable->{hdnProofQuantity}
			  : 												   $qty[$i];
		# Remove when possible.
        $variable->{"QUANTITY$i"}     = $qty[$i] unless $variable->{"QUANTITY$i"};

        $variable->{"txtQuantity$i"}  = $q;
        $variable->{"hdnQuantity$i"}  = $q;

    }
	
	$variable->{ADDRESSES} = $dbh->selectall_arrayref(q{
		SELECT * FROM tbl_addresses, ship_address WHERE lngindex = shipid AND sid = ?
	},{Slice => {}}, $sid);

     my @keys = qw(cost_center manualcostcenter accountnumber storemailinstructions department);


     map {
         foreach my $key (@keys) {
             $_->{$key} = $variable->{$key . '-'.$_->{shipid}};
         }
     } @{$variable->{ADDRESSES}};



	$variable->{COST_CENTERS} = $dbh->selectall_arrayref(q{
		SELECT * FROM cost_center ORDER BY name;
	},{Slice => {}});

	$variable->{USER_CENTERS} = $dbh->selectall_arrayref(q{
		SELECT * FROM user_cost_center WHERE user_id = ? ORDER BY cost_center;
	},{Slice => {}}, $variable->{user_id});



	map {$specs->{$_} = $variable->{$_}; } keys %{$variable};

	my $user_id;

	($user_id, $variable->{is_order}, $variable->{is_quote})  = $dbh->selectrow_array(q{
		SELECT lnguserindex, create_to_order, create_to_quote FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	eprint::user::load($log, $dbh, $user_id, $variable);

	$variable->{txtAddress1}   = $variable->{address1};
	$variable->{txtAddress2}   = $variable->{address2};
	$variable->{txtCity}       = $variable->{city};
	$variable->{txtPostalCode} = $variable->{postalcode};
	$variable->{txtCubicle}    = $variable->{cubicle};

	$variable->{txtCompanyName} = $dbh->selectrow_array(q{
		SELECT strcompanyname FROM tbl_customer WHERE lngcustomerid = (
			SELECT lngcustomerid FROM tbl_customer_users WHERE lnguserid = ? )
	}, undef, $user_id);


# Option will be selected by __FillInForm from Service Specs.
	$variable->{StateProvince}
        = ssi::return_states_and_provinces($variable->{state});
    $variable->{Country}
        = ssi::return_countries($variable->{country});

	my @time = localtime(time);
	my $year = 1900 + $time[5];

	if ( $variable->{ddmDueDateYear1} && $variable->{ddmDueDateYear1} < $year ) {
		push @{$variable->{YEARS}}, {year=>$variable->{ddmDueDateYear1}};
	}
		
	map { push @{$variable->{YEARS}}, {year=>$_+$year} } (0..3);

	$variable->{__FillInForml}{rdbSalutation} = $variable->{txtTitle};


return $variable;
}


sub shipping_summary {
		my ($r, $log, $dbh, $var, $pid) = @_;
		my $ships = $dbh->selectcol_arrayref(q{
			SELECT lngserviceindex FROM tbl_project_contents 
			WHERE lngprojectindex = ? AND strservicetype = 'Shipping'
		}, undef, $pid);
		map { 
			my $specs = eprint::docket::shipping($r, $log, $dbh, $pid, $_);
			push @{$var->{SHIPPING}}, $specs
		} @{$ships};
}


sub inventory_display {
    my ($r, $log, $dbh, $variable, $pid, $sid) = @_;

    # Do evreything needed to display the shipping page.
    eprint::print::get_product_specs($r, $log, $dbh, $pid, $sid, $variable);
    $$variable{'txtProjectWeight'} = get_weight($log, $dbh, $pid, 'Project')
      if $$variable{'txtProjectWeght'} eq '';
    foreach my $x (1 .. 3) {
        $$variable{ 'txtInventoryQty' . $x } = $$variable{ 'txtQuantity' . $x }
          if $$variable{ 'txtInventoryQty' . $x } eq '';
    }
}

sub print_labels {
	my ($r, $log, $dbh, $variable, $sid ) = @_;
	#Make all of the Information From the shipping service
	#Available for printing Labels.

	my $q = q{
		SELECT strname AS name, strvalue AS value FROM tbl_service_specifications 
		WHERE lngserviceindex = ?
	};

	my $address = $dbh->selectall_arrayref( $q,, undef, $sid);

	# Right now we only have one address per shipping service.
	@{$variable->{SHIP_ADR}} = { map { $_->[0], $_->[1]} @{$address} };

}
sub get_ship_info {
	my ($r, $log, $dbh, $pid, $qid) = @_;

		my @data;
		my $carton_sid 	= eprint::project::check_for_service( $log, $dbh, $pid, 'PlainCartons');
		my %cartons = $carton_sid 
					? eprint::service::get_specifications_pairs($log, $dbh, $pid, $carton_sid)
 					: undef;

		my $qpb = $cartons{txtItemsPerPackage};

		my $ships = $dbh->selectall_arrayref(q{
			SELECT shipid, sid FROM ship_address WHERE sid  in (
				SELECT lngserviceindex FROM tbl_project_contents
				 WHERE lngprojectindex = ?
			)
		}, undef, $pid);

		map {
			my $shipid = shift @{$_};
			my $sid    = shift @{$_};
			my %shipping 	= eprint::service::get_specifications_pairs(
													$log, $dbh, $pid, $sid);

			my $ship_qty = $shipping{"add_qty${qid}-$shipid"};
			my $add = eprint::address->new($log, $dbh, $shipid);
			my $address = $add->as_string();
			
			push @data, {
				sid 		=> $sid,
				shipid 		=> $shipid,
				item_qty 	=> $ship_qty,
				per_box 	=> $qpb,
				#boxes		=> $ship_qty % $qpb ? int($ship_qty / $qpb) + 1 : $ship_qty / $qpb,
				#weight  	=> sprintf("%.1f",$ship_qty * $cartons{hdnProjectWeight}),
				address 	=> $address 
			};


	
		} @{$ships};

		return @data;


}

1;
