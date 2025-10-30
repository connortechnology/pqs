package eprint::qprice;
use strict;

use POSIX qw(ceil);

use eprint::print_project ();
use eprint::project ();
use eprint::service qw(:specs);
use eprint::project_files ();
use Data::Dumper;


sub upload {
	my ($r, $dbh, $var) = @_;
print STDERR "GO UPLOAD -- COOKIE: $var->{cookie} \n";

	my $pid = $dbh->selectrow_array(q{
		SELECT max(lngprojectindex) FROM tbl_projects WHERE cookie = ?
	}, undef, $var->{cookie});

#	die("NO PID") unless $pid;

	$pid = eprint::print_project::dummy_project($r, $r->log, $dbh, $var->{cookie}, $var) unless $pid;
print STDERR "HAVE PID: $pid  UPLOAD \n";


	eprint::project_files::upload_files($r, $dbh, $var, $pid);

}
sub check_proj_req {
	my ($r, $dbh, $predefined) = @_;


	my $press_type = $r->param('auto_pid') ? $dbh->selectrow_array(q{
		SELECT strid FROM tbl_equipment_type e, tbl_projects p 
		WHERE e.lngindex = p.lngpresstype AND p.lngprojectindex = ?
	}, undef, $r->param('auto_pid')) : undef;

print STDERR "HAVE PRESS TYPE: $press_type \n";

	if ($press_type eq 'inkjetprinter') {
		return 'Inkjet';
	}
	if ( $r->param('ForceDigital') ) {
		return 'Digital';
	}
print STDERR "NOT DIGITAL OR LF: CONTIUE \n";

	my $data;
	my $val = q{ SELECT value FROM product.answer   WHERE id = ?  };

	my $spc = q{ SELECT spec, spec_type FROM product.question WHERE id = ?  };
print STDERR "2. NOT DIGITAL OR LF: CONTIUE \n";

	foreach my $p ( $r->param() ) {
#print STDERR "CHECK PARAM : $p \n";
		
		if ($p =~ /q(\d*)$/) {
			my $q = $1;
			my $a = $r->param($p);

			my ($spec, $type) = $dbh->selectrow_array($spc, undef, $q);
			my $val 		  = $dbh->selectrow_array($val, undef, $a);

#print STDERR "CHECK SPEC: $spec \n";
			if ( $spec eq 'size' ) {
#print STDERR "HAVE SIZE: $spec - $val \n";
				$data->{$spec} = [split('x',$val)];
			} elsif ( $spec eq 'colour' ) {
				$data->{$spec} = [split('/',$val)];
			} else {
				$data->{$spec} = $val;
			}

		} else {
			if ( $p eq 'cover_colour' ) {
				$data->{$p} = [split('/',$r->param($p))];
			} elsif ( $p eq 'size' ) {
				$data->{$p} = [split('x',$r->param($p))];
			} else {
				$data->{$p} = $r->param($p);
			}
		}
	}
print STDERR "DONE FOR EACH PARAM \n";

	my $s = 1;
	map {
		if ( $_ =~ /(\d*)\+(\d*)/ ) {
			$data->{"pms$s"} = $1;
			$_ = $1 + $2;
		}
		$s++;
	} @{$data->{colour}};

	$data->{pages} = $r->param('txtTotalPageQuantity') || 1;
	$data->{qty}   = $r->param('txtQuantity1');

	my $sides = $data->{colour}[1] ? 2 : 1;



# No longer charge 2 clicks for large items.
#	my $size  = $data->{size}[0] >= 17 || $data->{size}[1] >= 17
#				? 2 : 1;
# Still charge half clicks for small items.

	my $size = 1;
	$size = 0.5 if $data->{size}[0] <= 8.5 && $data->{size}[1] <= 8.5;



#If we have colour on both sides then set our colour mutplier to 2.	
	my $colour = 0;
	   $colour++ if $data->{colour}[0] > 1;
	   $colour++ if $data->{colour}[1] > 1;

	my $clicks = $data->{pages} > 1
			   ? $data->{qty} * $data->{pages} * $size 
			   : $data->{qty} * $sides * $size;  
			
	my $pms = $data->{pms1} || $data->{pms2};

	my $cal = $dbh->selectrow_array(q{
		SELECT strcalliper FROM tbl_paper WHERE strname = ?
		AND strcolour = ? AND strWeight = ? AND strFinish = ?
	}, undef, 
		$data->{stock_name},   $data->{stock_colour}, 
	    $data->{stock_weight}, $data->{stock_finish}
	);

print STDERR "HAVE CLICK COUNT: $clicks QTY: $data->{qty} Size: $size Colours: $colour\n";

	my $type = 'Digital';

	$type =  'Sheetfed' if int($clicks) > int(60000);
print STDERR "TYPE: $type CLICKS: $clicks \n";

	$type =  'Sheetfed' if $colour == 2 and $clicks > 1998;
	$type =  'Sheetfed' if $colour == 1 and $clicks > 2499;

	$type =  'Sheetfed' if $pms || $cal > 0.01;
	$type =  'Sheetfed' if $data->{size}[0] * $data->{size}[1] > 187; 


	my $pid = $type eq 'Sheetfed' ?  match_predef($r, $dbh, $data) : undef;

	return ($type, $pid);


}

sub match_predef {
	my ( $r, $dbh,  $data )  = @_;
	use eprint::service;
	my $debug;

	my $key_list = [qw(
		stock_name	stock_finish	stock_colour	stock_weight	
	)];

	my $match_key;
	my $cover_key;
	my ($w, $h, $fw, $fh ) = folded_size($r, $dbh, undef, $data->{size}[0], $data->{size}[1]);

	foreach my $x ( @{$key_list} ) {
		$match_key .= " $data->{$x} ";
		$cover_key .= " $data->{'cover_'.$x} ";
	}
	$match_key .= " $data->{colour}[0]/$data->{colour}[1]";
	$match_key .= " ${fw}x${fh}";
	$match_key .= " $data->{pages}";

	$cover_key .= " $data->{cover_colour}[0]/$data->{cover_colour}[1]";
	$cover_key .= " ${fw}x${fh}";
		
# Testing Only
#	my $list = $dbh->selectcol_arrayref(q{
#		SELECT lngprojectindex FROM tbl_projects 
#		WHERE strstatus = 'predefined'
#		AND lngprojectindex = 16042
#	});

	my $list = $dbh->selectcol_arrayref(q{
               SELECT lngprojectindex FROM tbl_projects 
               WHERE strstatus = 'predefined'
               AND lngprojectindex > 15890
	});
 


	map {
		my $pid = $_;
		my ($sid)  = eprint::project::get_signature_indices($r->log, $dbh, $pid);
		my $cover  = eprint::project::get_cover_sid($dbh, $pid);

		my $s = eprint::service::_from_db($dbh, $sid);
		


		my $c1 = $s->{s0_black}   ? 1 :
				 $s->{s0_process} ? 4 : 0;

		my $c2 = $s->{s1_black}   ? 1 : 
				 $s->{s1_process} ? 4 : 0;

		$c1++ if $s->{s0_pms_1_name};
		$c1++ if $s->{s0_pms_2_name};
		$c1++ if $s->{s0_pms_3_name};
		$c1++ if $s->{s0_pms_4_name};

		$c2++ if $s->{s1_pms_1_name};
		$c2++ if $s->{s1_pms_2_name};
		$c2++ if $s->{s1_pms_3_name};
		$c2++ if $s->{s1_pms_4_name};

		
		my $key;
		foreach my $x ( @{$key_list} ) {
			$key .= " $s->{$x} ";
		}
		$key .= " $c1/$c2";
		my $w = $s->{flat_width};
		$w = $dbh->selectrow_array(q{
			SELECT strvalue FROM tbl_service_specifications WHERE lngprojectindex = ?
			AND strname = 'flat_width'
		}, undef, $pid) unless $w;

		my $h = $s->{flat_height};
		$h = $dbh->selectrow_array(q{
			SELECT strvalue FROM tbl_service_specifications WHERE lngprojectindex = ?
			AND strname = 'final_height'
		}, undef, $pid) unless $h;

		my $p = $dbh->selectrow_array(q{
			SELECT strvalue FROM tbl_service_specifications WHERE lngprojectindex = ?
			AND strname = 'txtTotalPageQuantity'
		}, undef, $pid) || 1;
		

		$key .= " ${w}x$h";
		$key .= " $p";
		$debug .= "PID: $pid SID: $sid COV: $cover " . Dumper($key);


		if ( $key eq $match_key ) {
			print STDERR "FOUND MATCH: $key PID: $pid \n";
			return $pid;
		} else { 
#			print STDERR "NO MATCH: $key \n";
		}
	} @{$list};

	print STDERR "NO FOUND MATCH: $match_key \n";

	return undef;

} 

sub get_base_project {
	my ($r, $dbh) = @_;

#more logic to be added later.
#Base project id is now in the 
#product template.
	my $pid = $r->param('auto_pid');

	return $pid;

}


sub auto_product {
	my ($r, $dbh, $var, $predefined) = @_;

	$predefined = get_base_project($r, $dbh);

	my $pid;

	my ($type, $product) = check_proj_req($r, $dbh, $predefined);
print STDERR "CLICKS DONE CHECK: HAVE TYPE: $type, $product \n";

	if ( $type eq 'Digital' || $type eq 'Inkjet' ) {
		my $pid = eprint::print_project::create_project($r, $r->log, $dbh, $var->{cookie}, $var, undef, $predefined, undef);
		
		# new_pid comes from create_project.	
		$pid = $var->{new_pid};

		insert_services($r, $dbh, $pid);

		insert_product_specs($r, $dbh, $pid);

		if ( $r->param('ForceDigital') ) {
			notify_force_digital($r, $dbh, $pid);
		}



	} else {
		if ( $product ) {
print STDERR "MAKE FROM PRODUCT: $product TYPE: $type \n";
			eprint::print_project::create_project($r, $r->log, $dbh, $var->{cookie}, $var, undef, $product, undef );
			$pid = $var->{new_pid};
		} else {
print STDERR "SEND HTTP_MOVED_TEMPORARILY FOR PROJECT NOTIFICATION \n";

			my $id = $dbh->selectrow_array(q{SELECT nextval('hybrid_rec')});

			record_specs($r, $dbh, undef, $id);

			$r->headers_out->set( Location => "/main/proj/project_notification.html?id=$id");
		 	
			return;
		}
		
	}

	$pid = $var->{new_pid};
	record_specs($r, $dbh, $pid);
	add_delivery_date($r, $dbh, $pid);

	$dbh->do(q{
		UPDATE tbl_projects SET cookie = ? WHERE lngprojectindex = ?
	}, undef, $var->{cookie}, $pid) if $pid;

	return $pid;
}

sub record_specs {
	my ($r, $dbh, $pid, $id) = @_;

	$id = $dbh->selectrow_array(q{SELECT nextval('hybrid_rec')}) unless $id;

	my $ins = $dbh->prepare(q{ INSERT INTO hybird_specs VALUES ( ?, ?, ?, ? ) });

	my $val = q{ SELECT value FROM product.answer   WHERE id = ?  };
	my $spc = q{ SELECT spec  FROM product.question WHERE id = ?  };

	map { 
		
		my $name = $_;
		my $value = $r->param($_); 


		if ($_ =~ /q(\d*)$/) {
			my $q = $1;
			my $a = $r->param($_);

			($name) = $dbh->selectrow_array($spc, undef, $q);
			 $value = $dbh->selectrow_array($val, undef, $a);
		}

		if ( $name eq 'service' ) {
			map { 
				$ins->execute($pid, $_, $_, $id);
			} $r->param('service');
		} else {
			$ins->execute($pid, $name, $value, $id);
		}

	} $r->param();


	
}

sub add_delivery_date{
	my ($r, $dbh, $pid) = @_;

	my $sid = eprint::print_project::insert_service($r->log, $dbh, $pid, 'Shipping');

#	my $sid = eprint::project::check_for_service(undef, $dbh, $pid, 'Shipping');

	my $ins = $dbh->prepare(q{
		INSERT INTO tbl_service_specifications VALUES ( ?,?,?,?,? )
	});

	map {
		print STDERR "INSERTING: $_ \n ";
		$ins->execute($pid, $sid, $_, $r->param($_), 'true')
	} qw(ddmDueDateDay1 ddmDueDateMonth1 ddmDueDateYear1 ddmDueDateTime);

}


sub folded_size {
	my ($r, $dbh, $pid, $flatw, $flath) = @_;
	my ($w, $h);
	
	my $type = $r->param('FoldType');

	return ( $flatw, $flath, $flatw, $flath ) unless $type;

# reverse dimensions for folding cuz most folded
# projects have a landscape orientation.
#	my $x = $flatw;

#	$flatw = $flath;
#	$flath = $x;

print STDERR "DIMS: ($flatw, $flath, $w, $h) \n";
	if ( $type eq 'txt2PanelFoldQty' ) {
		$w = $flath / 2;	
		$h = $flatw;
	} elsif ( $type eq 'txt3PanelZFoldQty' 	) {
		$w =  $flath == 11   ? 3.66
		    : $flath == 14   ? 4.66
			: $flath == 17   ? 5.66
			: $flath == 25.5 ? 8.5  
			: $flath / 3;
		$h = $flatw;
    } elsif (   $type eq 'txt3PanelRollFoldQty'  ) {
         $w =  $flath == 11 ? 3.66
			 : $flath == 14 ? 4.66
             : $flath == 17 ? 5.66
             : $flath == 25 ? 8.5 
			 : $flath / 3;
         $h = $flatw;
	} elsif (  $type eq 'txt4PanelRollFoldQty' 
			|| $type eq 'txt4PanelZFoldQty'		) {
		$w =  $flath == 14 ? 3.5
			: $flath == 22 ? 5.5
			: $flath / 4;
		$h = $flatw;
	} elsif ( $type eq 'txtDoubleGateFolded' ) {
		$w = $flath == 14 ? 3.5
			: $flath == 22 ? 5.5
			: $flath /4 ;
		$h = $flatw;
	}
	$w = sprintf("%.3f", $w) + 0;
print STDERR "DIMS: ($flath, $flatw, $w, $h) \n";
	
	return ($flath, $flatw, $w, $h);
	

}



sub insert_services {
	my ($r, $dbh, $pid ) = @_;

	map {
		my $sid = eprint::print_project::insert_service($r->log, $dbh, $pid, $_);

		eprint::service::insert_service_spec(
			$r->log, $dbh, $pid, $sid, 'txtQuantity1',$r->param('txtQuantity1')
		) if $sid;

		if ( $_ eq 'Drilling' ) {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtHoleQty',3);
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtHoleSize'    ,0.25);
		} elsif ($_ eq 'Bundle') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtWrapQuantity',$r->param('txtWrapQuantity'));
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'rdbBundleType','ElasticBand');
		} elsif ($_ eq 'ShrinkWrap') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtWrapQuantity',$r->param('txtShrinkWrapQuantity'));
		} elsif ($_ eq 'HandAssembly') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'rdbHandAssemblyType','Simple');
		} elsif ($_ eq 'Folding') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, $r->param('FoldType'),'1');
		} elsif ($_ eq 'Laminating') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 's0_laminate', $r->param('LamType'));
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 's1_laminate', $r->param('LamType'));
		} elsif ($_ eq 'Mounting') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'mounting_type', 'Foamcore0.1875White');
		} elsif ($_ eq 'Scanning') {
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtPercent', $r->param('txtPercent'));
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'ddmOriginal', $r->param('ddmOriginal'));
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtQuantity', $r->param('txtQuantity'));
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtScanWidth',  1);
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtScanHeight', 1);
			eprint::service::insert_service_spec($r->log, $dbh, $pid, $sid, 'txtScanHeight', 1);
		}

	} $r->param('service');
	

}


sub notify_force_digital {

    my ( $r, $dbh, $pid ) = @_;

	my $info = $dbh->selectrow_hashref(q{
		SELECT * FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	my $file = q{/email/content/digital_override.html};

	my $email = $dbh->selectrow_array(q{
		select notificationemail from tbl_customer where strcompanyname = 'SAFEWAY';
	});

    my %mail = (
         SMTP    => configuration::get_value( $r->log, $dbh, 'Mail Server'),
         FROM    => $email,
         TO    	 => $email,
         SUBJECT => "Digital Project Override"
    );

	misc::email_with_template($r, $r->log, $dbh, $file, \%mail, $info);

}

sub insert_product_specs {
	my ($r, $dbh, $pid) = @_;
	
	$dbh->do(qq{UPDATE tbl_projects SET product = true WHERE lngprojectindex = $pid});

	my $val = q{ SELECT value FROM product.answer   WHERE id = ?  };
	my $spc = q{ SELECT spec, spec_type FROM product.question WHERE id = ?  };

	my $wup = $dbh->prepare(q{
		UPDATE tbl_service_specifications set strvalue = ?
		WHERE strname IN ('txtSpreadWidth', 'final_width', 'flat_width', 'txtScanWidth')
		AND lngprojectindex = ?
	});

	my $hup = $dbh->prepare(q{
		UPDATE tbl_service_specifications set strvalue = ?
		WHERE strname IN ('txtSpreadHeight', 'final_height', 'flat_height', 'txtScanHeight')
		AND lngprojectindex = ?
	});

	my $final_width = $dbh->prepare(q{
		UPDATE tbl_service_specifications set strvalue = ?
		WHERE strname IN ('final_width') AND lngprojectindex = ?
	});
	my $final_height = $dbh->prepare(q{
		UPDATE tbl_service_specifications set strvalue = ?
		WHERE strname IN ('final_height') AND lngprojectindex = ?
	});

	my $up = $dbh->prepare(q{
		UPDATE tbl_service_specifications SET strvalue = ? 
		WHERE strname = ? AND lngprojectindex = ?
		
	});


	my $sid_up = $dbh->prepare(q{
		UPDATE tbl_service_specifications SET strvalue = ? 
		WHERE strname = ? AND lngprojectindex = ? AND lngserviceindex = ?
	});


	my $ins = $dbh->prepare(q{
		INSERT INTO tbl_service_specifications VALUES ( ?,?,?,?,? )
	});

	my $cdel = $dbh->prepare(q{
		DELETE FROM tbl_service_specifications WHERE lngprojectindex = ?
		AND strname IN ( 's0_black','s0_process', 's1_black','s1_process' )
		AND lngserviceindex NOT IN (
				SELECT lngserviceindex FROM tbl_service_specifications
				WHERE lngprojectindex = ? AND strname = 'txtServiceDescription'
				AND strvalue = 'Binder Tabs'
		)
	});

	$dbh->do(qq{ DELETE FROM tbl_service_specifications WHERE lngprojectindex = $pid
				AND strname IN ( 'txtShippingCompanyName', 'ddmShippingStateProvince', 'txtShippingAddress1',
								 'txtShippingCity', 'txtShippingPhone', 'txtShippingPostalCode', 
								 'txtShippingContact', 'ddmShippingCompany'
	)});
	$dbh->do(qq{ DELETE FROM ship_address WHERE sid IN 
					(SELECT lngserviceindex FROM tbl_project_contents WHERE lngprojectindex = $pid) } );

# Update paper info
#	$up->execute($r->param('stock'), 'hdnPaperIndex', $pid);


	my $colour = $r->param('stock_colour');
	my $weight = $r->param('weight');
	
	my $sids = $dbh->selectcol_arrayref(q{
		SELECT lngserviceindex FROM tbl_project_contents WHERE lngprojectindex = ?
			AND strservicetype = 'Printing'
			AND lngserviceindex NOT IN ( 
			SELECT lngserviceindex FROM  tbl_service_specifications
				WHERE lngprojectindex = ?  AND  strname = 'txtServiceDescription' AND strvalue = 'Binder Tabs' 
		);
	}, undef, $pid, $pid);

	map {
		$sid_up->execute($r->param('stock_name'),   'stock_name',   $pid, $_);
		$sid_up->execute($r->param('stock_finish'), 'stock_finish', $pid, $_);
		$sid_up->execute($r->param('stock_colour'), 'stock_colour', $pid, $_);
		$sid_up->execute($r->param('stock_weight'), 'stock_weight', $pid, $_);
	} @{$sids};


	$dbh->do("DELETE FROM tbl_service_specifications WHERE lngprojectindex = $pid AND strname = 'override_press'");
    $dbh->do("DELETE FROM tbl_service_specifications WHERE lngprojectindex = $pid AND strname = 'press'");

	if ( $r->param('mv_qty') ) {
		my $sid = eprint::project::get_print_container($r->log, $dbh, $pid);
        my @name  = $r->param('mv_name');
        my @qty  =  $r->param('mv_qty');
print STDERR "HAVE MULTIVERSION STUFF " , Dumper(@name, @qty);
		        my (@versions, @quantities);


		my $total = $r->param('txtQuantity1');
        # For now mirror the JS precisely. Note: Multiple labels of the
        # same name are allowed and treated as different versions.
        for my $i (0 .. $#qty) {
            my $name    = $name[$i];
            my $qty     = int($qty[$i]);

            next unless $qty > 0;

            my $percent = ($qty / $total) * 100;

            if ($name and $percent and ceil($percent) > 0) {
                push @versions,   $name => $percent;
                push @quantities, $name => $qty;
            }
        }
		$ins->execute($pid, $sid, 'is_mv', '1', 'true');
		$ins->execute($pid, $sid, 'versions', join(',', @versions) ,  'true');
		$ins->execute($pid, $sid, 'version_quantities', join(',', @quantities) ,  'true');

	}
print STDERR "DONE MULIT VERSION STUFF \n\n\n\n";


	if ( $r->param('Pads') ) {

		# Change project type to Scratch Pads.
		$dbh->do(q{
			UPDATE tbl_projects SET lngprojecttype = 15 WHERE lngprojectindex = ?	
		}, undef, $pid);

		#Update printing Service.
		my $print = eprint::project::get_print_container($r->log, $dbh, $pid);
		$ins->execute($pid, $print, 'pad_sheets', $r->param('pad_sheets'), 'true');

		#Insert padding Service.
		my $sid = eprint::print_project::insert_service($r->log, $dbh, $pid, 'Padding');
		$ins->execute($pid, $sid, 'pad_sheets', $r->param('pad_sheets'), 'true');
		$ins->execute($pid, $sid, 'rdbCardboardBacking', $r->param('rdbCardboardBacking'), 'true') 
			if $r->param('rdbCardboardBacking');

	}
	if ( $r->param('size') ) {

		my $w = $r->param('width');
		my $h = $r->param('height');

		my ( $w, $h, $fw, $fh ) = folded_size($r, $dbh, $pid, $w, $h);

		$wup->execute($w, $pid);
		$hup->execute($h, $pid);

		$final_width->execute( $fw, $pid);
		$final_height->execute($fh, $pid);


	}

	if ( $r->param('Bindery') ) {

		# Insert Punching here cuz there is no template for using Corner Stiching
		# and 3 Hole punch on the same project.
		if ( $r->param('Bindery') eq 'CornerStitch3Punch' ) {
			eprint::print_project::insert_service($r->log, $dbh, $pid, '3HolePunch');
		}

		my $sides = $r->param('CoverType') =~ /Index/ + $r->param('BackCoverType') =~ /Index/;
		my $clear = $r->param('CoverType') =~ /Clear/ || 0;
		my $black = $r->param('BacKCoverType') =~ /Black/ || 0;
		my $binder = $r->param('Bindery') eq '3HolePunchBinder' ? 1 : 0;
		my $colours = $r->param('back_colour');

		$dbh->do(q{
			INSERT INTO cover_specs VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
		}, undef, $pid, $r->param('back_stock_name') || '',   $r->param('back_stock_finish') || '',
						$r->param('back_stock_colour') || '', $r->param('back_stock_weight') || '',
						$sides, $clear, $black, $binder, $colours );
		
		if ( $clear || $black ) {
			my $sid = eprint::print_project::insert_service($r->log, $dbh, $pid, 'Cover');
			my $ins = $dbh->prepare(q{
				INSERT INTO tbl_service_specifications VALUES ( ?,?,?,?,? )
			});

			$ins->execute($pid, $sid, 'ddmFrontCover', 'ClearCovers', 'true') if $clear;
			$ins->execute($pid, $sid, 'ddmBackCover',  'Black Back',  'true') if $black;

		}

		my $book = $dbh->selectrow_array(q{
			SELECT lngserviceindex FROM tbl_project_contents 
			WHERE  lngprojectindex = ? AND strservicetype = 'Book'
		}, undef, $pid);
		
		$ins->execute($pid, $book, 'no_bindery', '1', 'true') 
			if $r->param('Bindery') =~ 'NoBindery';

		$ins->execute($pid, $book, 'SlipSheets', '1', 'true') 
			if $r->param('Bindery') eq 'NoBinderySlipSheet';
		if ( $r->param('Tabs') ) {
			local *spec = sub {
				my ($name, $value) = @_;
				insert_service_spec( $r->log, $dbh, $pid, $book, $name,$value, undef, 1);
			};
			
			my  $bind = $r->param('Bindery');
			my $pages = $r->param('txtTotalPageQuantity') / 2;
			my  $tabs = $r->param('txtTabsQuantity');
		
print STDERR "INSERTING TABS INTO: $book *** \n\n";

			spec('TabsYes',1);
			
#			$ins->execute($pid, $book, 'TabsYes', 1, 'true');

			spec('txtTotalSpreadQuantity', $pages);
#			$sid_up->execute( $pages, 'txtTotalSpreadQuantity', $pid, $book);

			spec('rdbGateFold', 'Yes');
#			$sid_up->execute( 'Yes',  'rdbGateFold', $pid, $book);

##			$sid_up->execute( $tabs,  'GateFolded Spreads', $pid, $book);
##			$ins->execute($pid, $book, 'txtGateFoldedSpreadQuantity', $tabs, 'true');

			spec('txtGateFoldedSpreadQuantity', $tabs);
#			$sid_up->execute( $tabs, 'txtGateFoldedSpreadQuantity', $pid, $book);

			spec('txtTabsQuantity', $tabs);
#			$sid_up->execute( $tabs,  'txtTabsQuantity', $pid, $book);



		} else {
			$sid_up->execute( '',  'txtTabsQuantity', $pid, $book);
			$sid_up->execute( '',  'TabsYes', $pid, $book);
			$sid_up->execute( 'No',  'rdbGateFold', $pid, $book);
		}
my $x = $dbh->selectall_hashref(q{
		SELECT * from tbl_service_specifications WHERE lngserviceindex = ?
},'strname', {Slice=>{}}, $book);
print STDERR "HAVE STUFF" , Dumper($x);



	}

	if ( $r->param('cover_stock_name') ) {
		my $sid  = eprint::project::get_cover_sid($dbh, $pid);
		$sid_up->execute($r->param('cover_stock_name'),   'stock_name',   $pid, $sid);
		$sid_up->execute($r->param('cover_stock_finish'), 'stock_finish', $pid, $sid);
		$sid_up->execute($r->param('cover_stock_colour'), 'stock_colour', $pid, $sid);
		$sid_up->execute($r->param('cover_stock_weight'), 'stock_weight', $pid, $sid);

	} elsif ( $r->param('back_stock_name') ) {
		my $sid  = eprint::project::get_cover_sid($dbh, $pid);
		$sid_up->execute($r->param('back_stock_name'),   'stock_name',   $pid, $sid);
		$sid_up->execute($r->param('back_stock_finish'), 'stock_finish', $pid, $sid);
		$sid_up->execute($r->param('back_stock_colour'), 'stock_colour', $pid, $sid);
		$sid_up->execute($r->param('back_stock_weight'), 'stock_weight', $pid, $sid);


	}
#		map {
#			$ins->execute($pid, $sid, "back_stock_$_", $r->param("back_stock_$_"), 0);
#		} qw(name finish colour weight);

	if ( $r->param('CoverType') =~ /Self/ && $r->param('BackCoverType') =~ /Self/ ) {
		$up->execute('Self', 'rdbCover', $pid);
	}

	foreach my $p ( $r->param() ) {
		if ($p =~ /q(\d*)$/) {
			my $question = $1;
			my $answer = $r->param($p);

			my ($spec, $type) = $dbh->selectrow_array($spc, undef, $question);
			my ($value)       = $dbh->selectrow_array($val, undef, $answer);

print STDERR "QUESTION: $question $spec - Answer: $answer $value \n";
		
			my $b = $r->param('Bindery');

			if ( $spec eq 'size' ) {
				my ($fw, $fh);
				my ($w,$h) = split('x',$value);
			 	( $w, $h, $fw, $fh ) = folded_size($r, $dbh, $pid, $w, $h);

				print STDERR "HAVE WIDTH: $w HEIGHT: $h FINAL $fw x $fh \n";
				$wup->execute($w, $pid);
				$hup->execute($h, $pid);

				$final_width->execute($fw, $pid);
				$final_height->execute($fh, $pid);

				if ( $r->param('Bindery') eq 'SaddleStitching' ) {
print STDERR "UPDATING SPREAD WIDTH: $w * 2 \n";
					$up->execute($w * 2, 'flat_width', $pid);
					$up->execute('Different', 'rdbCover', $pid);

				}
			}
			elsif ( $spec eq 'colour' ) {

print STDERR "START COLOUR \n";

				my $cover_sid;
				my $cover = $r->param('cover_colour') || $r->param('back_colour');
				if ( $cover ) {
					$cover_sid  = eprint::project::get_cover_sid($dbh, $pid);
				};
				my $inside = $value;

				my $list = $dbh->selectcol_arrayref(q{
					SELECT DISTINCT lngserviceindex FROM tbl_service_specifications 
					WHERE lngprojectindex = ? AND 
					strname IN ( 's0_black','s0_process', 's1_black','s1_process' )
					AND lngserviceindex NOT IN (
						SELECT lngserviceindex FROM tbl_service_specifications
						WHERE lngprojectindex = ? AND strname = 'txtServiceDescription'
						AND strvalue = 'Binder Tabs'
					)
				}, undef, $pid, $pid);

				$cdel->execute($pid, $pid);
			

				map {
					$value =  $_ == $cover_sid ? $cover : $inside;
					my ($f,$b) = split('/',$value);
						print STDERR "HAVE COLOUR SID: $_ F: $f B: $b \n";

					if ( $f == 1 ) {
						$ins->execute($pid, $_, 's0_black', 1, 'true');
					} elsif ( $f == 4 ) {
						$ins->execute($pid, $_, 's0_process', 1, 'true');
					}

					if ( $b == 1 ) {
						$ins->execute($pid, $_, 's1_black', 1, 'true');
					} elsif ( $b == 4 ) {
						$ins->execute($pid, $_, 's1_process', 1, 'true');
					}
				} @{$list};
			
			}
			elsif ( $type eq 'printing' ) {
				$up->execute($value, $spec, $pid);
			}
		}
		elsif ( $p eq 'txtTotalPageQuantity' ) {
			$up->execute($r->param($p), $p, $pid);
		}
		elsif ( $p eq 'Bindery' ) {
			my $bind = $r->param($p);
			$bind = 'CornerStitching' if $bind eq 'CornerStitch3Punch';
			$up->execute($bind, 'template', $pid);
		} 
	
	}




	
	

}




1;

__END__

