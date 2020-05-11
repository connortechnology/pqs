package eprint::docket;
use strict;
use warnings;
no warnings qw(uninitialized);

use Apache2::Const qw(:common);
use Apache2::Log ();
use Data::Dumper;
use MIME::QuotedPrint;
use POSIX qw(ceil);
use Scalar::Util qw(looks_like_number);


use ssi;
use sql;
use jsrs;
use eprint::project qw(:common);
use eprint::service qw(:common);
use eprint::equipment ();
use eprint::Config;
use eprint::employee_project;
use eprint::Service::Book;

#require eprint::rfq;
require eprint::order;
require eprint::print_project;
require eprint::Service::Collating;

use PQS::model::service;
use PQS::model::materials;

use constant QTY => 1;
use constant DISPLAY_TIME_DATA => eprint::Config->get(Docket => 'display_time_data');

our %RUN_STYLE = (
    SW => 'Sheet Work',
    WT => 'Work & Turn',
    WF => 'Work & Flop', # Tumble
    PF => 'Perfecting',
);
sub round ($;$) {my($n,$s)=@_;$s=(defined $s)?$s:2;int($n*10**$s+0.5)/10**$s}

our %switch = (
    Film                => \&film,
    InkMixing           => \&ink_mixing,
    Printing            => \&printing,
    Cutting             => \&cutting,
    Proofs              => \&proofs,
    PlateMaking         => \&plate_making,
    Proclick            => \&spiral,
    CornerStitching     => \&spiral,
    '3HolePunch'        => \&spiral,
    'SingleHole'        => \&spiral,
    Fastback            => \&spiral,
    DoubleLoopWire      => \&binding,
    LoopStitching       => \&binding,
    MetalCoil           => \&binding,
    PlasticCoil         => \&binding,
    PerfectBinding      => \&binding,
    SaddleStitching     => \&binding,
    Scoring             => \&scoring,
    ImpositionLayout    => \&imposition_layout,
    MetalCoil           => \&spiral,
    PlasticCoil         => \&spiral,
    Cerlox              => \&spiral,
    DoubleLoopWire      => \&spiral,
    Collating           => \&collating,
    DieCutting          => \&die_cutting,
    KissCutting         => \&die_cutting,
    Folding             => \&folding,
    PolyBagging         => \&polybagging,
    BulkSkids           => \&bulk_skids,
    Bundles             => \&bundles,
    KraftWrap           => \&kraft_wrap,
    PlainCartons        => \&plain_cartons,
    ShrinkWrap          => \&kraft_wrap,
    Grommeting          => \&grommet,
    Welding             => \&simple_hardware,
    ICutting            => \&simple_hardware,
    Stitching           => \&simple_hardware,
    Rope                => \&rope,
    Postage             => \&postage,
    Shipping            => \&shipping,
    Mounting            => \&mounting,
);

# Used to get the quantity of a given
# service type.
sub get_quantity {
    my ($log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my $sth = $dbh->prepare(
        q{
        SELECT s.strvalue
        FROM tbl_service_specifications s, tbl_project_contents p
        WHERE p.lngserviceindex = s.lngserviceindex
          AND p.lngprojectindex = ?
          AND p.lngserviceindex = ?
          AND s.strname IN ('txtQuantity', 'txtQuantity' || ?::int)
        ORDER BY s.strname DESC
        LIMIT 1
    });
    return scalar $dbh->selectrow_array($sth, undef, $pid, $sid, $qtyIndex);
}

sub RFQ_calc : JSRS {
    my ($r, $log, $dbh, $variable, @suppliers) = @_;
	return unless @suppliers;

    my %ddm;
	my @data;
    my $sth = $dbh->prepare(q{
        SELECT strcompanyname AS comp_name, stremail    AS email, 
			   strfirstname   AS firstname, strlastname AS lastname, 
			   strsalutation  AS salutation
          FROM tbl_customer_users, tbl_customer
         WHERE tbl_customer_users.lngcustomerid = tbl_customer.lngcustomerid 
		   AND tbl_customer_Users.lngcustomerid = ?
		   AND tbl_customer_Users.ysnaccountactivation = 'Y'
	  ORDER BY strfirstname, strlastname
    });
	
	map {
		my $customer_info = $dbh->selectall_arrayref($sth, { Slice => {} }, $_);

    	for my $cust (@$customer_info) {
			push @data,  $cust->{email},
            	" ( $cust->{comp_name} ) $cust->{salutation} $cust->{firstname} $cust->{lastname}";
        	$ddm{ $cust->{email} } 
            	= "( $cust->{comp_name} ) $cust->{salutation} $cust->{firstname} $cust->{lastname}";
    	}
	} @suppliers;
#    return \%ddm;
    return \@data;
}

sub RFQ {
    my ($r, $log, $dbh, $variable) = @_;
    setup_RFQ($r, $log, $dbh, $variable);
    $variable->{rid} = eprint::rfq::create_rfq( $r, $dbh );
    return OK;
}

sub setup_RFQ {
    my ($r, $log, $dbh, $variable) = @_;


    # $ssi::INVALID_KEY = 1;
    my @servicesIDs = $r->param('rfq');
    if (!@servicesIDs) {
        @servicesIDs = split(',', $r->param('Services'));
    }
    my $pid = $r->param('pid');
    $pid = $r->param('ProjectIndex') unless $pid;
    my ($qtyIndex, $qty) = $dbh->selectrow_array(q{
        SELECT intquantityIndex, intquantity
        FROM tbl_order_contents
        WHERE lngprojectindex = ?
    }, undef, $pid);
    return if !$pid;
    my $service_type = $dbh->prepare(q{
        SELECT lower(t.strid) AS ref, t.strname AS name , p.lngserviceindex AS ID, t.strid AS strID
        FROM tbl_service_types t, tbl_project_contents p
        WHERE ( t.strid = p.strservicetype OR (p.strservicetype is null AND t.strid = 'Printing' ))
        AND p.lngprojectindex = ?
        AND p.lngserviceindex = ?
    });
    my $tmp;
    my @services;
    my @materials;
	my $printids = $dbh->selectall_hashref(q{
		SELECT lngserviceindex as sid FROM tbl_project_contents
		WHERE lngprojectindex = ? AND strservicetype = 'Printing';
	}, 'sid',  {}, $pid ); 
    for my $serviceID (@servicesIDs) {
        $tmp =
          $dbh->selectall_arrayref($service_type, { Slice => {} },
                                   $pid, $serviceID);
        $tmp = shift @$tmp;
        my $qty       = get_quantity($log,  $dbh, $pid, $serviceID, $qtyIndex);
        my $equipment = get_equipment($log, $dbh, $pid, $serviceID, $qtyIndex);
        my $comment = scalar $dbh->selectrow_array(q{
            SELECT strComments
            FROM tbl_project_contents
            WHERE lngserviceindex = ?
            AND lngprojectindex =?
        }, undef, $serviceID, $pid);

        my ($data, $material) =
          summary($r, $log, $dbh, $pid, $serviceID, $qtyIndex, $tmp->{'name'});
        
        push @materials, $_ for @{$material};

        push @services, { 
            ref       => $tmp->{'ref'},
            name      => $tmp->{'name'},
            qty       => $qty,
            equipment => $equipment,
            sid       => $serviceID,
            comment   => $comment,
            html      => ssi::variable_substitution($r, $log, $dbh,
                            ssi::insert_html($r, "/includes/main/docket/service_type/" . $tmp->{'ref'} . ".html"),
                            $data
                        ),
        };
		delete $printids->{$serviceID};
    }

	# Get Material Information For any Print Services that were
	# not part of the RFQ Services.
	map { my ($d, $m) = summary($r, $log, $dbh, $pid, $_, $qtyIndex, 'Printing'); 
	      push @materials, @{$m} 
		} keys %{$printids};

    materials($log, $variable, @materials);
    my @suppliers;
    $tmp = $dbh->selectall_arrayref(q{
        SELECT lngcustomerid , strcompanyname
        FROM tbl_customer
        WHERE ysnsupplier = 'Y'
    }, undef,);

    for my $supplier (@$tmp) {
        push @suppliers, shift @$supplier;
        push @suppliers, shift @$supplier;
    }


    $variable->{serviceIDs}    = join(',', @servicesIDs);
    $variable->{Suppliers}     = ssi::make_drop_down(\@suppliers);
    $variable->{administrator} = $variable->{user}{name};
    if (!$variable->{administrator}) {
        my @name = $dbh->selectrow_array(q{
            SELECT  strfirstname, strlastname
            FROM tbl_customer_users
            WHERE lnguserid = ?
        }, undef, $variable->{user_id});
        $variable->{administrator} = join(' ', @name);
    }
    my @qtys = get_quantities($log,  $dbh, $pid);

    my @date = gmtime;
    $variable->{rfq}{date_created} =
      ($date[5] + 1900) . '-' . $date[4] . '-' . $date[3];
    $variable->{QtyIndex}        = $qtyIndex;
    $variable->{ProjectIndex}    = $pid;
    $variable->{RFQ}             = \@services;
    $variable->{HeaderInfo}      = header_info($log, $dbh, $pid);
    $variable->{OrderedQuantity} = $qty || join(', ',@qtys);
    my $order_id = $r->param('order_id');
    $variable->{order_id}  = $order_id;
    $variable->{docketcss} =
      ssi::insert_html($r, "site_specific/styles/docket.css");
    $variable->{admincss} =
      ssi::insert_html($r, "site_specific/styles/administrator.css");
}

sub send_rfq_email {
    my ($r, $log, $dbh, $variable) = @_;

    eprint::rfq::send_rfq( $r, $dbh, $variable );

    return OK;

    setup_RFQ($r, $log, $dbh, $variable);
    my $order_id = $variable->{order_id};
    return unless $order_id;

    my @emails = $r->param('users');

    eprint::order::get_invoice_to($log, $dbh, $variable, $order_id);
    eprint::order::get_ship_to($log, $dbh, $variable, $order_id);
    eprint::order::get_misc($log, $dbh, $variable, $order_id);
    $variable->{'CCITYPROVCOUNTRY'} =
      misc::build_city_prov_country(
                     @$variable{ 'txtCity', 'txtStateProvince', 'txtCountry' });
    $variable->{'FCITYPROVCOUNTRY'} =
      misc::build_city_prov_country(
                              @$variable{
                                  'txtShippingCity', 'txtShippingStateProvince',
                                  'txtShippingCountry'
                                });
    $variable->{'ORDER_ID'} = $order_id;
    $variable->{'siteURL'}  = "http://" . $r->hostname;

    my $email_template = misc::load_file($r, '/email/forms/rfq.html');
    $_ =
      encode_qp(
        ssi::variable_substitution($r, $log, $dbh, $email_template, $variable));
    my @body = ('', $_, 'text/html', 'quoted-printable');
    my $email_addr = join(',', @emails);
    my %mail = (
          SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          TO      => $email_addr,
          SUBJECT => "RFQ",);
    misc::send_email_with_attachment($r, $log, \%mail, @body);
    return OK;
}

# Dispatch Function used to return information about a given
# service type.
sub summary {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex, $sname, $form_count) = @_;

    my $service_type = $sname eq 'Inkjet Printing'   ? 'Inkjet'
                     : $sname eq 'Imposition Layout' ? 'ImpositionLayout'
                     : $sname eq 'Ink Mixing'        ? 'InkMixing'
                     :               eprint::service::service_type($dbh, $sid);


    my $data;
    my $materials;

    if (exists $switch{$service_type}) {
        ($data, $materials) =
          $switch{$service_type}->($r, $log, $dbh, $pid, $sid, $qtyIndex, $form_count);
    }
    else {
        $data = fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex);
		foreach my $i (1..3) {
			if ( $data->{"ddmEquipment$i"} ) {
				$data->{"ddmEquipment$i"} =
				eprint::equipment::get_id_by_index( $log, $dbh, $data->{"ddmEquipment$i"}); 
			}
		}
    }

    	$data->{RunTime} = get_specifications($log, $dbh, undef, $sid, "hdnRunTime$qtyIndex") if $sid;
    	$data->{RunTime} = $data->{RunTime} ? sprintf("%.2f",$data->{RunTime}) : undef; 

	#kludgerama!
	$data->{ProjectType} =~ s/^LF_/Large Format /;

    return $data, $materials;
}

sub comment {
    my ($r, $log, $dbh, $variable) = @_;
    my $sid = $r->param('ServiceID');
    my $pid = $r->param('ProjectIndex');

    return if !$pid;

    my $comment = $r->param('Comment');
	my $trackingnumber = $r->param('trackingnumber');
	my $ctype = $r->param('CommentType');

map { print STDERR "HAVE PARAM COMM: $_ = " . $r->param($_) . "\n" } $r->param();
	
	$variable->{CommentType} = $ctype;

	print STDERR "UPDATE SPEICAL COMMENT: $ctype --$comment.\n";

	if ( $ctype ) {
		if ($r->param('Save')) {
			sql::update(
				$log, $dbh, 'tbl_projects', "lngprojectindex = $pid",
				$ctype, $comment
			) if $comment;


			$dbh->do(qq{ update tbl_projects SET $ctype = NULL WHERE lngprojectindex = ?}, undef, $pid) unless $comment;
		}

    	($comment) = $dbh->selectrow_array( qq{
            SELECT $ctype
            FROM tbl_projects
            WHERE lngprojectindex =?
    	}, undef, $pid);
	}
	else
	{
		sql::update(
			$log, $dbh, 'tbl_project_contents', "lngprojectindex = $pid AND
		lngserviceindex = $sid", 'strcomments', $comment) if $r->param('Save');

		sql::update(
			$log, $dbh, 'tbl_project_contents', "lngprojectindex = $pid AND
		lngserviceindex = $sid", 'trackingnumber', $trackingnumber) if $trackingnumber;


    	($comment, $trackingnumber) = $dbh->selectrow_array( q{
            SELECT strcomments, trackingnumber
            FROM tbl_project_contents
            WHERE lngserviceindex = ?
              AND lngprojectindex =?
    	}, undef, $sid, $pid);

	}

    my $AdminName = $r->param('AdministratorName');
    $variable->{sid}          	   = $sid;
    $variable->{Comment}      	   = $comment;
    $variable->{ProjectIndex} 	   = $pid;
	$variable->{trackingnumber}    = $trackingnumber;
    $variable->{AdministratorName} = $AdminName;
    $variable->{order_id} = scalar $dbh->selectrow_array( q{
            SELECT lngorderid
            FROM tbl_order_contents
            WHERE lngprojectindex = ?
        }, undef, $pid);


	$variable->{is_shipping} = scalar $dbh->selectrow_array(q{
		SELECT count(*) from tbl_project_contents 
		WHERE lngserviceindex = ? AND strservicetype = 'Shipping'
	}, undef, $sid) if $sid;

    if ( $r->param('change_notification') ) {
        my $email  = configuration::get_value($log, $dbh, 'ProductionChangeEmail');
        my $content = { comments    => $comment,
                        pid         => $pid
                      };

        my $email_template = misc::load_file($r, '/email/forms/change_notification.html');

        $_ = encode_qp( ssi::variable_substitution($r, $log, $dbh, 
                                               $email_template, $content));
        my @body = ('', $_, 'text/html', 'quoted-printable');
        my %mail = (
            SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
            FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
            TO      => $email,
            SUBJECT => "Change Notification",);

        misc::send_email_with_attachment($r, $log, \%mail, @body);
    }

    return OK;
}

sub service_summary {
    my ($r, $log, $dbh, $variable, $is_docket) = @_;


    my $pid = $r->param('ProjectIndex');
    return if !$pid;

    my $sid = $r->param('ServiceIndex');
    return if !$sid;

    my $url = $r->header_in('Referer');

    my $qtyIndex = scalar $dbh->selectrow_array(q{
        SELECT intquantityIndex
        FROM tbl_order_contents
        WHERE lngprojectindex = ?
    }, undef, $pid);

    my $name = eprint::service::service_type($dbh, $sid) || 'Printing';
    my $ref  = "\L$name";

    my ($data) = summary($r, $log, $dbh, $pid, $sid, $qtyIndex, '');
    my $qty       = get_quantity($log,  $dbh, $pid, $sid, $qtyIndex);
    my $equipment = get_equipment($log, $dbh, $pid, $sid, $qtyIndex);
    my $order_id = $r->param('Order_id') || $r->param('OrderID');

    my $expectedDate;
    my $status;
    my $type = 'quote';

    if ($order_id) {
        $expectedDate = scalar $dbh->selectrow_array(
            q{
            SELECT daterequired
            FROM tbl_order_contents
            WHERE lngorderid = ?
        }, undef, $order_id);

        $status = scalar $dbh->selectrow_array(
            q{
            SELECT strstatus 
            FROM tbl_orders
            WHERE lngorderid = ?
        }, undef, $order_id);
        $type = 'order';
    }

    my %serviceType = (
                      name      => $name,
                      qty       => $qty,
                      equipment => $equipment,
                      html      =>
                        ssi::variable_substitution(
                          $r, $log, $dbh,
                          ssi::insert_html(
                              $r, "/includes/main/docket/service_type/$ref.html"
                          ),
                          $data
                        ),
                      requiredDate => $expectedDate,
                      status       => $status,
                      type         => $type,);

    $variable->{'EmployeeDocket'} = \%serviceType;
    $variable->{'ProjectIndex'}   = $pid;
    $variable->{'ServiceIndex'}   = $sid;
    $variable->{order_id}         = $order_id;
    $variable->{url}              = $url;
    return OK;
}


# The following functions get all of the information need
# used to populate the html ssi variables.  It uses
# get_specifications in service.pm which to get at
# any information that was at the service page (i.e.
# for die cutting, it can get anyinformation which is in the
# HTML on the die cutting page).  Then it puts this information into
# an hash and returns a reference to it.


# SERVICE PROCEDURES:
sub collating {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    return eprint::Service::Collating::display($log, $dbh, undef, $pid, $sid);
}

sub cutting {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    require eprint::Service::Cutting;
    return eprint::Service::Cutting::display($log, $dbh, 'Cutting', $pid, $sid, {});
}


sub spiral {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    my %hash;
    my $print_sid = get_print_container($log, $dbh, $pid);

    $hash{height}    = get_specifications($log, $dbh, undef, $print_sid, 'final_height');
    $hash{qty}       = get_specifications($log, $dbh, undef, $sid, "txtQuantity$qtyIndex");
    $hash{ddmBinder} = get_specifications($log, $dbh, undef, $sid, "ddmBinder");
    $hash{binder_name} = eprint::material::get_name($dbh, $hash{ddmBinder});

    $hash{calliper}  = eprint::project::get_finished_calliper($log, $dbh, {}, $pid);
    $hash{mqty}      = $hash{height} * $hash{qty};

    return \%hash;
}
sub mounting {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };

    $hash{mounting_name} = $dbh->selectrow_array(q{
		SELECT strname FROM tbl_materials WHERE strid = ?
	}, undef, $hash{mounting_type} );

    return \%hash;
}

sub inventory {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    $hash{txtInventoryQty} = $hash{"txtInventoryQty$qtyIndex"};
    return \%hash;
}

sub plain_cartons {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    $hash{hdnSkidQuantity} = $hash{"hdnSkidQuantity$qtyIndex"};
    $hash{txtCartonWeight} = $hash{"txtCartonWeight$qtyIndex"};
    return \%hash;
}

sub kraft_wrap {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    ($hash{'txtQuantity1'}, $hash{'txtQuantity2'}, $hash{'txtQuantity3'}) =
      split /,/, $hash{'txtQuantity'};
    $hash{txtQuantity} = $hash{"txtQuantity$qtyIndex"};
    return \%hash;
}

sub bundles {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    $hash{txtQuantity} = $hash{"txtQuantity$qtyIndex"};
    return \%hash;
}

sub bulk_skids {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    $hash{hdnSkidQuantity} = $hash{"hdnSkidQuantity$qtyIndex"};
    return \%hash;
}

sub polybagging {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    $hash{txtBagQuantity} = $hash{"txtBagQuantity$qtyIndex"};
    return \%hash;
}

sub folding {
    my ($r, $log, $dbh, $pid, $sid, $q) = @_;
    my %hash = %{ fill_info($r, $log, $dbh, $pid, $sid, $q) };

    $hash{"ddmEquipment$q"} = 
		eprint::equipment::get_id_by_index($log, $dbh , $hash{"ddmEquipment$q"}) 
		if looks_like_number($hash{"ddmEquipment$q"});

	my $equip = $dbh->selectrow_array(q{
		SELECT strvalue FROM tbl_service_specifications
		WHERE strname ~ 'Sig-Equipment'
		AND lngserviceindex = ?
	}, undef, $sid);

	if ( $equip && $equip ne $hash{"ddmEquipment$q"} ) {
    	$equip = eprint::equipment::get_id_by_index(
										$log, $dbh , $equip);
		$hash{"ddmEquipment$q"} .=  ", $equip";
	}
    return \%hash;
}

sub die_cutting {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash =
      eprint::service::get_specifications_pairs(
                       $log,                        $dbh,
                       undef,                       $sid,
                       'rdbHoleClearing',           'rdbDieCutting',
                       'rdbSuppliedDie',            'txtDieWidth',
                       'txtDieHeight',              'txtSteelRuleLengthSimple',
                       'txtSteelRuleLengthAverage', 'txtSteelRuleLengthComplex',
                       'txtDieCutBends',            'txtHoleClearingHoles',
                       'txtDieCutPunches',          'Glued',
					   'rdbGlued',					"ddmEquipment$qtyIndex",
					   'rdbBusinessCardStyle',		'rdbBusinessCardSlot',
					   'template',					'txtImposition1',
					   'txtImposition2',			'txtImposition3',
					   );
    my $type = $hash{"rdbDieCutting"};
    $hash{'show'} = 1
      if $hash{'rdbSuppliedDie'} eq 'N';
    $hash{'txtSteelRuleLength'} = $hash{"txtSteelRuleLength$type"};
    if ($hash{'rdbHoleClearing'} eq 'Y') {
        $hash{'rdbHoleClearing'} = 'Yes';
    }
    else {
        $hash{'rdbHoleClearing'} = 'No';
    }
	$hash{rdbGlued} = $hash{Glued} unless $hash{rdbGlued};

	# For Presentation Folders we must get the Gluing option
	# from the printing service.
	$hash{rdbPocketSize} = $dbh->selectrow_array(q{
		SELECT strvalue FROM tbl_service_specifications
		WHERE  lngprojectindex = ? and strname = 'rdbPocketSize'
	}, undef, $pid) unless $hash{rdbPocketSize};

	$hash{rdbGlued} = $dbh->selectrow_array(q{
		SELECT strvalue FROM tbl_service_specifications
		WHERE  lngprojectindex = ? and strname = 'rdbGlued'
	}, undef, $pid) unless $hash{rdbGlued};

    if ($hash{'rdbGlued'} eq 'Y') {
        $hash{'rdbGlued'} = 'Yes';
    }
    elsif ( $hash{'rdbGlued'} eq 'N' ) {
        $hash{'rdbGlued'} = 'No';
    }

    if ($hash{'rdbSuppliedDie'} eq 'Y') {
        $hash{'rdbSuppliedDie'} = 'Yes';
    }
    else {
        $hash{'rdbSuppliedDie'} = 'No';
    }
	if ( $hash{template} =~ '2Pocket' ) {
		$hash{pockets} = 2;
	}
	elsif ( $hash{template} =~ '1Pocket' ) {
		$hash{pockets} = 1;
	}
	else {
		$hash{pockets} = ' Custom ';
	}
	$hash{rdbPocketSize} = $dbh->selectrow_array(q{
		SELECT strvalue FROM tbl_service_specifications
		WHERE  lngprojectindex = ? and strname = 'rdbPocketSize'
	}, undef, $pid);

	foreach my $i (1..3) {
		if ( $hash{"ddmEquipment$i"} ) {
			$hash{"ddmEquipment$i"} =
			eprint::equipment::get_id_by_index( $log, $dbh, $hash{"ddmEquipment$i"}); 
		}
	}


    return \%hash;
}

sub proofs {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %proofHash;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);
    my $multi = eprint::project::is_multipage($log, $dbh, $pid);
    my @proof_info = @{
        $dbh->selectall_arrayref(
            q{
        SELECT strvalue AS value, strname AS name
        FROM tbl_service_specifications
        WHERE lngserviceindex = ? 
          AND (strname ~* 'txtProofQuantity' OR strname ~* 'txtProofWidth' OR strname ~* 'txtProofHeight' OR strname ~* 'ddmProofType') 
      }, { Slice => {} }, $sid
        ) };
    my %tmphash;
    for my $proofspec (@proof_info) {
        $$proofspec{name} =~ /[\w*\s*]-(\d+)-(\d+)/;
        my $tmp1 = $1;
        my $tmp2 = $2;
        $$proofspec{name} =~ /[\w*\s*]Proof(\w+)-\d+-\d+/;
        my $name = $1;
        $tmphash{$tmp1}{$tmp2}{$name} = $$proofspec{value};
    }
    foreach my $sigIndex (@signature_service_indices) {
        my ($ref, $signatureIndex) =
          eprint::service::get_specifications($log, $dbh, undef, $sigIndex,
                                    "txtServiceDescription", "SignatureIndex",);
        my @proofs;
        for my $key (keys %{ $tmphash{$sigIndex} }) {
            my ($qty, $width, $height, $type) = (
                                      $tmphash{$sigIndex}{$key}{Quantity},
                                      $tmphash{$sigIndex}{$key}{Width},
                                      $tmphash{$sigIndex}{$key}{Height},
                                      $tmphash{$sigIndex}{$key}{Type});
            push @proofs,
              { ProofQuantity => $qty,
                ProofWidth    => $width,
                ProofHeight   => $height,
                ProofType     => $type, };
        }
        push @{ $proofHash{'signature'} },
          { Reference => $ref,
            proofs    => \@proofs,
            multipage => $multi, };
    }

    return \%proofHash;
}

sub film {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);
    my $multi = eprint::project::is_multipage($log, $dbh, $pid);
    foreach my $sigIndex (@signature_service_indices) {
        my ($ref, $signatureIndex) =
          get_specifications($log, $dbh, undef, $sigIndex,
                                    "txtServiceDescription", "SignatureIndex",);
        my ($type, $Emulsion, $qty, $width, $height, $screen) =
          get_specifications($log,
                             $dbh,
                             undef,
                             $sid,
                             "rdbFilmType-$signatureIndex",
                             "rdbEmulsion-$signatureIndex",
                             "txtFilmQuantity-$signatureIndex",
                             "txtFilmWidth-$signatureIndex",
                             "txtFilmHeight-$signatureIndex",
                             "txtLineScreen-$signatureIndex",);
        push @{ $hash{'signature'} },
          { Reference       => $ref,
            rdbFilmType     => $type,
            rdbEmulsion     => $Emulsion,
            txtFilmQuantity => $qty,
            txtFilmWidth    => $width,
            txtFilmHeight   => $height,
            txtLineScreen   => $screen, };
    }
    return \%hash;
}

sub plate_making {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash;

    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);

    my $multi = eprint::project::is_multipage($log, $dbh, $pid);

    foreach my $sigIndex (@signature_service_indices) {
        my ($ref) = eprint::service::get_specifications(
						$log, $dbh, undef, $sigIndex, "txtServiceDescription");
        my ($qty, $type) = eprint::service::get_specifications( 
			$log, $dbh, undef, $sid,
			"txtPlateQuantity-$sigIndex", "ddmPlateType-$sigIndex"
	 	);

        push @{ $hash{'signature'} }, { 
			reference        => $ref,
            txtPlateQuantity => $qty,
            ddmPlateType     => $type,
            multipage        => $multi, 
	    };
    }

    return \%hash;
}

sub scoring {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);
    my $multi = eprint::project::is_multipage($log, $dbh, $pid);
    foreach my $sigIndex (@signature_service_indices) {
        my ($ref) =
          eprint::service::get_specifications($log, $dbh, undef, $sigIndex,
                                              "txtServiceDescription");
        my ($scoreQty, $perfQty, $equip, $imp) =
          eprint::service::get_specifications($log, $dbh, undef, $sid,
                "txtScoreQty-$sigIndex", 			"txtPerfQty-$sigIndex", 
				"ddmEquipment$qtyIndex-$sigIndex",	"txtImposition$qtyIndex-$sigIndex",
				);
		$equip = eprint::equipment::get_id_by_index($log, $dbh, $equip);
        push @{ $hash{'signature'} },
          { Reference   => $ref,
            txtScoreQty => $scoreQty,
            txtPerfQty  => $perfQty,
            multipage   => $multi,
            equipment   => $equip, 
			txtImposition => $imp
		  };
    }

    return \%hash;
}

sub simple_hardware {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    my %specs = eprint::service::get_specifications_pairs(
        $log, $dbh, $pid, $sid
    );

    my ($device) = $dbh->selectrow_array(
        "SELECT strname FROM tbl_equipment WHERE lngindex = ?",
        undef, $specs{hdnDevice}
    );

    return { Device => $device,
             %specs            };
}

sub grommet {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    my %specs = %{ simple_hardware($r, $log, $dbh, $pid, $sid, $qtyIndex) };

    my ($grommet) = $dbh->selectrow_array(
        "SELECT strname FROM tbl_materials WHERE lngindex = ?",
        undef, $specs{ddmGrommet}
    );

    return { GrommetType => $grommet,
             %specs                   };
}

sub rope {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    my %specs = %{ simple_hardware($r, $log, $dbh, $pid, $sid, $qtyIndex) };

    my ($rope) = $dbh->selectrow_array(
        "SELECT strname FROM tbl_materials WHERE lngindex = ?",
        undef, $specs{ddmRopeType}
    );

    return { RopeType => $rope,
             %specs                   };
}
sub shipping {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    my %specs = eprint::service::get_specifications_pairs(
        $log, $dbh, $pid, $sid
    );
	my $sql = q{ SELECT * FROM tbl_addresses, ship_address WHERE lngindex = shipid AND sid = ?  };
	my $shipid = $r->param('shipid');
	$sql .= qq{ AND tbl_addresses.lngindex = $shipid } if $shipid;

	$specs{ADDRESSES} = $dbh->selectall_arrayref($sql,{Slice => {}}, $sid);

	my @keys = qw(add_price1 add_price2 add_price3 add_qty1 add_qty2 add_qty3 cost_center pickup manualcostcenter accountnumber storemailinstructions department);

	map { 
		foreach my $key (@keys) {
			$_->{$key} = $specs{$key . '-'.$_->{shipid}};
		}
	} @{$specs{ADDRESSES}};

	$specs{order_id} = $dbh->selectrow_array(q{
		SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $pid);
	$specs{pid} = $pid;
    return \%specs;

}

sub postage {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;

    my %specs = eprint::service::get_specifications_pairs(
        $log, $dbh, $pid, $sid
    );

    $specs{ddmPostage} = $dbh->selectrow_array(
        "SELECT name FROM sub_service_type WHERE id = ?",
        undef, $specs{ddmPostage}
    );

    return \%specs;
}

sub binding {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash;
    my $index = eprint::project::get_print_container($log, $dbh, $pid);
    my ($cover, $insertQty, $gateFold) =
      eprint::service::get_specifications($log, $dbh, undef, $index, "rdbCover",
                                        "txtInsertQuantity", "rdbGateFoldFit",);
    $insertQty += 0;
    my ($pockets,      $twoQty,      $fourQty,
        $sixQty,       $eightQty,    $twelveQty,
        $sixteenQty,   $twentyQty,   $twentyfourQty,
        $thirtytwoQty, $gateFoldQty, $doubleGateFoldQty);
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);

    foreach my $sigIndex (@signature_service_indices) {
        my ($tmptwoQty,      $tmpfourQty,       $tmpsixQty,
            $tmpeightQty,    $tmptwelveQty,     $tmpsixteenQty,
            $tmptwentyQty,   $tmptwentyfourQty, $tmpthirtytwoQty,
            $tmpgateFoldQty, $tmpdoubleGateFoldQty)
          = eprint::service::get_specifications(
            $log,                    $dbh,
            undef,                   $sigIndex,
            "txtSignatureQty2Page",  "txtSignatureQty4Page",
            "txtSignatureQty6Page",  "txtSignatureQty8Page",
            "txtSignatureQty12Page", "txtSignatureQty16Page",
            "txtSignatureQty20Page", "txtSignatureQty24Page",
            "txtSignatureQty32Page", "txtSignatureQtyGateFolded",
            "txtSignatureQtyDoubleGateFolded",);

        $twoQty            += $tmptwoQty;
        $fourQty           += $tmpfourQty;
        $sixQty            += $tmpsixQty;
        $eightQty          += $tmpeightQty;
        $twelveQty         += $tmptwelveQty;
        $sixteenQty        += $tmpsixteenQty;
        $twentyQty         += $tmptwentyQty;
        $twentyfourQty     += $tmptwentyfourQty;
        $thirtytwoQty      += $tmpthirtytwoQty;
        $gateFoldQty       += $tmpgateFoldQty;
        $doubleGateFoldQty += $tmpdoubleGateFoldQty;

        $pockets =
            $twoQty      + $fourQty           + $sixQty 
          + $eightQty    + $twelveQty         + $sixteenQty 
          + $twentyQty   + $twentyfourQty     + $thirtytwoQty 
          + $gateFoldQty + $doubleGateFoldQty;
    }

    $gateFold = undef if ($gateFoldQty < 1 && $doubleGateFoldQty < 1);

    %hash = (
        rdbCover                        => $cover,
        txtInsertQuantity               => $insertQty,
        rdbGateFoldFit                  => $gateFold,
        txtSignatureQty2Page            => $twoQty,
        txtSignatureQty4Page            => $fourQty,
        txtSignatureQty6Page            => $sixQty,
        txtSignatureQty8Page            => $eightQty,
        txtSignatureQty12Page           => $twelveQty,
        txtSignatureQty16Page           => $sixteenQty,
        txtSignatureQty20Page           => $twentyQty,
        txtSignatureQty24Page           => $twentyfourQty,
        txtSignatureQty32Page           => $thirtytwoQty,
        txtSignatureQtyGateFolded       => $gateFoldQty,
        txtSignatureQtyDoubleGateFolded => $doubleGateFoldQty,
        Page1                           => '',
        Page2                           => '',
        Width                           => '',
        Height                          => '',
        Pockets                         => $pockets,
    );
    ($hash{'txtEquipment1'}) = 
            eprint::service::get_specifications($log, $dbh, undef, $sid, "txtEquipment1");
    $hash{'txtEquipment1'} = $dbh->selectrow_array(q{
        SELECT strname FROM tbl_equipment WHERE lngindex = ?
    }, undef, $hash{'txtEquipment1'}); 

    foreach (1..3) {
        my $x = "hdnRunTime$_";
        $hash{$x} = eprint::service::get_specifications($log, $dbh, undef, $sid, $x);
    }

    $hash{'UseStaples'} = eprint::service::get_specifications($log, $dbh, undef, $sid, "UseStaples") eq "n" ? "No" : "Yes";

    ($hash{'txtEquipment1'}) = 
            eprint::service::get_specifications($log, $dbh, undef, $sid, "txtEquipment1");
    $hash{'txtEquipment1'} = $dbh->selectrow_array(q{
        SELECT strname FROM tbl_equipment WHERE lngindex = ?
    }, undef, $hash{'txtEquipment1'}); 

    return \%hash;
}

sub get_equipment {
    my ($log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my $sth = $dbh->prepare(
        q{
    SELECT s.strvalue
    FROM tbl_service_specifications s, tbl_project_contents p
    WHERE p.lngserviceindex = s.lngserviceindex
      AND p.lngprojectindex = ?
      AND p.lngserviceindex = ?
      AND s.strname ~* ('^(ddm|txt)Equipment' || ?::int || '?$')
        ORDER BY substring(s.strname from '.$') DESC, s.strname
    LIMIT 1
    });
    return scalar $dbh->selectrow_array($sth, undef, $pid, $sid, $qtyIndex);
}

sub printing {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex, $form_count) = @_;


	my $type = eprint::project::get_type($log, $dbh, $pid);


	return { NoPrint => 1}, [] if $type eq 'NoPrint';


	
    use Compress::LZF qw(:compress :freeze);
    use Storable              qw(thaw);
    use MIME::Base64;

    if ( $r->param('customovers') ne '' ) {
	    my $overs = $r->param('customovers');
	    my $sid = $r->param('sid');

	    $dbh->do("DELETE FROM tbl_service_Specifications WHERE lngserviceindex = $sid AND strname = 'CustomOvers'");
	    $dbh->do("INSERT INTO tbl_service_Specifications VALUES ( $pid, $sid, 'CustomOvers', $overs, true)");
	    print STDERR "CUSTOM OVERS: $sid, $overs \n";

    }
    my %hash;
    my $signatureIndex            = 0;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);
    my $multi = is_multipage($log, $dbh, $pid);
    my $userType = scalar $dbh->selectrow_array(
        q{
    SELECT chrType
    FROM tbl_customer_users
    WHERE lnguserid =
        (SELECT lngcustomerid
         FROM tbl_projects
         WHERE lngprojectindex = ?
        )
    }, undef, $pid);

    my %results = %{ fill_info($r, $log, $dbh, $pid, $sid, $qtyIndex) };
    my $press_type = scalar $dbh->selectrow_array(
        q{
    SELECT strid
    FROM tbl_equipment_type
    WHERE lngindex = 
        ( SELECT lngpresstype
          FROM tbl_projects
          WHERE lngprojectindex = ?
        )
    }, undef, $pid);
	$results{pressType} = $press_type;
    my $project_type = scalar $dbh->selectrow_array(
        q{
    SELECT strid
    FROM tbl_projecttypes
    WHERE lngindex = 
        ( SELECT lngprojecttype
          FROM tbl_projects
          WHERE lngprojectindex = ?
        )
    }, undef, $pid);
    if ($project_type eq 'ScreenItem') {
        my %hash =
          eprint::service::get_specifications_pairs(
                         $log,
                         $dbh,
                         undef,
                         eprint::project::get_print_container($log, $dbh, $pid),
                         'txtItemWidth',
                         'txtItemHeight',
                         'txtItemDepth',
                         'txtScreenPrintingItemWeight',
                         'txtScreenPrintingSurfaces',);
        foreach my $key (keys %hash) {
            $results{$key} = $hash{$key};
        }
        $results{screen} = 1;
    }
    else {
        $results{plate} = 1;
          my %hash = eprint::service::get_specifications_pairs(
                         $log,
                         $dbh,
                         undef,
                         eprint::project::get_print_container($log, $dbh, $pid),
                         'mvmpinfo',
                         'num_versions');
 		map { $results{$_} = $hash{$_} } keys %hash;
    }


    if ($multi) {
        if (!$results{hdnGrainDirection}) {
            ($results{hdnGrainDirection}) =
              eprint::service::get_specifications($log, $dbh, undef,
                                               shift @signature_service_indices,
                                               "hdnGrainDirection",)
        }
    }
    else {
        $results{single} = 1;
    }
    print STDERR "HAVE CUSTOM RESULts $results{'CustomOvers'} \n";
    $results{txtServiceDescription} = $results{ProjectType}
      if (!(eprint::project::is_multipage($log, $dbh, $pid)));

	my $specs = $dbh->selectall_hashref(q{
		SELECT strname as name, strvalue as value 
		FROM tbl_service_specifications 
		WHERE lngserviceindex = ?
	},'name', undef, $sid );

	# Needed for Material (paper) info.
	$results{txtSignatureQuantity} = $specs->{txtSignatureQuantity}{value};
	
	for my $s ( 's0','s1' ) {
		my %inks;
		$inks{std}  .= ' Black' if $specs->{$s.'_black'}{value};
		$inks{std}  .= ' CMYK'  if $specs->{$s.'_process'}{value};

		for my $i ( 1..8 ) {
			if ( $specs->{$s."_pms_".$i."_name"}{value} ) {
                    my ($ink_name) = $dbh->selectrow_array("select strname from tbl_materials where strid = ?", undef, $specs->{$s."_pms_".$i."_type"}{value});
				$inks{pms}  .= $ink_name . " ";
				$inks{pms}  .= $specs->{$s."_pms_".$i."_name"}{value} . " (";
				$inks{pms}  .= $specs->{$s."_pms_".$i."_coverage"}{value} . "%) ";
			}
		}

		$inks{varnish} .= ' Overall '. $specs->{$s."_varnish_flood"}{value}   
								if $specs->{$s."_varnish_flood"}{value};

		$inks{varnish} .= ' Spot ' . $specs->{$s."_varnish_spot"}{value} 
								if $specs->{$s."_varnish_spot_gloss"}{value} || 
								   $specs->{$s."_varnish_spot_matte"}{value}  
                                ;

		$inks{varnish} .= ' Dry Trap'   if $specs->{$s."_drytrap"}{value};

		$inks{lf_coverage} = $specs->{$s.'_ink_coverage'}{value} * 100;
		$inks{lf_quality}  = $specs->{$s.'_quality'}{value};
        $inks{chem_emboss} = $specs->{$s.'_chem_emboss'};

		if ( $specs->{$s."_coating_type"}{value} ) {
			$inks{coating} .= "Spot " if $specs->{$s."_coating_spot"}{value};
			$inks{coating} .= $specs->{$s."_coating_type"}{value};
			$inks{coating} .= " " . $specs->{$s."_coating_texture"}{value};
		};

		$inks{side} = $s eq 's0' ? 1 : 2;

		push @{ $results{SIDE}  }, \%inks if ( $inks{std} || $inks{pms} );

		if ( $specs->{side_link}{value} ) {
			my %s1_inks = %inks;
			$s1_inks{side} = 2;
			push @{ $results{SIDE} }, \%s1_inks;
			last;
		}
	}

    $results{'s0_coating_type'} = undef
      if ($results{'s0_coating_type'} eq 'None');

    $results{'s1_coating_type'} = undef
      if ($results{'s1_coating_type'} eq 'None');

    if ($results{'s0_coating_type'}) {
        if ($results{'s0_coating_type'} =~ /UV/) {
            $results{'AS1'} = 1;
        }
        else {
            $results{'UVS1'} = 1;
        }
    }

    if ($results{'s1_coating_type'}) {
        if ($results{'s1_coating_type'} =~ /UV/) {
            $results{'AS2'} = 1;
        }
        else {
            $results{'UVS2'} = 1;
        }
    }


    $results{'rdbPressProof'} = 'No'
      if (!$results{'rdbPressProof'});
    if (   ($results{s0_varnish_flood})
        || ($results{s0_varnish_flood})
        || ($results{s0_varnish_spot_gloss})
        || ($results{s0_varnish_spot_mattej})
        || ($results{s0_drytrap}))
    {
        $results{varnishOne} = 1;
    }
    else {
        $results{varnishOne} = 0;
    }

    if (   ($results{s1_varnish_flood})
        || ($results{s1_varnish_flood})
        || ($results{s1_varnish_spot_gloss})
        || ($results{s1_varnish_spot_matte})
        || ($results{s1_drytrap}))
    {
        $results{varnishTwo} = 1;
    }
    else {
        $results{varnishTwo} = 0;
    }
    my @materials;
    my $paper;

	$results{hdnSuppliedStockHeight} = $specs->{hdnSuppliedStockHeight}{value};
	$results{hdnSuppliedStockWidth}  = $specs->{hdnSuppliedStockWidth}{value};

    my $stock = $dbh->selectall_hashref(q{
        SELECT strname, strvalue FROM tbl_service_specifications
        WHERE lngserviceindex = ? AND strname ~ 'stock'
    },'strname',{}, $sid);

    map { $results{$_} = $stock->{$_}{strvalue} } keys %{$stock};




    my $alt_name =   " $results{stock_name} $results{stock_finish}" 
                   . " $results{stock_colour} $results{stock_weight} ";

	my $cover = $dbh->selectrow_hashref(q{
		SELECT * FROM cover_specs WHERE pid = ?
	}, undef, $pid);
	$results{cover} = $cover;

	($results{back_colour1}, $results{back_colour2}) = split('/',$cover->{back_colours});


# GET qtys FROM individual stock colours specified for multi-coloured pads.
# Not used anywhere but the docket.

	$results{MultiColour} = $dbh->selectall_arrayref(q{
		SELECT substring(name from 14) as name, value 
		FROM   hybird_specs WHERE name ~ 'multi-colour' and pid = ? AND value <> ''
	}, {Slice => {}},, $pid); 


	map {
		$results{"back_stock_$_"} = $cover->{$_};
	} keys %{$cover}; 
    
    if (   ($results{'stock_supplied'} ne 'Yes')
        && ($project_type ne 'ScreenItem'))
    {
        my $coated;
        if ($results{'pressType'} ne 'web') {
	  
		my $forms		= $results{txtSignatureQuantity};
	  	my $parent_sheets	= $results{hdnPaperBuyQuantity1} * $forms; 
	  	my $sheet_height	= $results{hdnPaperBuyQuantity1} * $forms; 
	
		#$paper = "F: $forms PS: $parent_sheets SH: $sheet_height ";
	

            $paper .=  $results{"hdnSheetSizeHeight"} . "x" . $results{"hdnSheetSizeWidth"};  

            $paper .= $results{"stock_name"};
            $paper .= " - " . $results{"txtSpecificStockBrand"}
              if $results{"txtSpecificStockBrand"};
            $paper .= ", "
              . $results{"stock_finish"} . ", "
              . $results{'stock_colour'} . ", "
              . $results{"stock_weight"} . ", "
              . $results{"txtStockCalliper"}
			  ;

            if (
                ( 
                  $results{'hdnSuppliedStockHeight'} != $results{'hdnSheetSizeHeight'} or
                  $results{'hdnSuppliedStockWidth'} != $results{'hdnSheetSizeWidth'}
                )
                and
                (
                  $results{'hdnSuppliedStockHeight'} and $results{'hdnSuppliedStockWidth'}
                )

               )
            {

    $results{'PaperOut'}     = ceil($results{'hdnSheetQuantity1'} / $results{hdnPaperBuyQuantity1}) if  $results{hdnPaperBuyQuantity1} ;
    		my $sheetHeight = $results{txtStockCalliper} * $results{hdnPaperBuyQuantity1};


           	$paper .= "<br/> Cut From ";
                $paper .= 
                  $results{'hdnSuppliedStockHeight'} . "x"
                . $results{'hdnSuppliedStockWidth'} . " "
		. " " . $results{PaperOut} . " Out"
		. " Parent Sheet Count: " . $results{'hdnPaperBuyQuantity1'} 
		. " Parent Sheet Height " . $sheetHeight
		;
            }

	    #$paper .= " "
	    #  . $results{"hdnSheetSizeHeight"} . "x"
	    #  . $results{"hdnSheetSizeWidth"} . " - " 
	    #        if ( $results{"hdnSheetSizeHeight"} && $results{"hdnSheetSizeWidth"} );

	
        }
        else {
            $paper = 
                $results{"hdnSheetSizeHeight"} . "x"
              . $results{"hdnSheetSizeWidth"} . " - "
              . $results{"stock_name"} . ", "
              . $results{"stock_finish"} . ", "
              . $results{'stock_colour'} . ", "
              . $results{'stock_weight'} . ", "
			  . " Paper Weight (pounds): "  . $results{'hdnPaperBuyQuantity'.$qtyIndex}
			  ;

        }
        $results{'txtSignatureQuantity'} = 1
          if ($results{'txtSignatureQuantity'} < 1);
        $results{'paper'} = $paper;
        push @materials,
          { category => "Paper",
            name     => $paper,
            alt_name => $alt_name,
            qty      => $results{"hdnSheetQuantity$qtyIndex"}, 
	    #qty      => $results{"hdnSheetQuantity$qtyIndex"} *
	    #  $results{'txtSignatureQuantity'}, }

    	  }

    }

    $results{hdnPress}
        = eprint::equipment::get_id_by_index($log, $dbh, $results{hdnPress});

    $results{'QtyIndex'}         = $qtyIndex;
    $results{'hdnSheetQuantity'} = $results{"hdnSheetQuantity$qtyIndex"};
    $results{'hdnNetSheetCount'} = $results{"hdnNetSheetCount$qtyIndex"};
    if ($results{'stock_supplied'}) {
        $results{'CustomerSupplied'} = 'Yes';
    }
    else {
        $results{'CustomerSupplied'} = 'No';
    }

    # Retrieve this services imposition information
    my $imp = sthaw(decode_base64($specs->{imp}{value}));
	my $runstyle = $imp->{style};

	# Std Project qtys from project.pm
    my @qtys = get_quantities($log,  $dbh, $pid);
    my $qty  = $qtys[$qtyIndex-1];

    if ($imp and (@{$imp->{layout}} > 1 or @{$imp->{layout}[0]} > 1)) {
        # If there's more than one version, list the versions. We don't care
        # what sheet they're on, just the version information.
		my $i;
		foreach my $f (@{ $imp->{layout} }) {

			my %form;

			$form{VERSIONS} = [ 
				sort { $a->{requested_qty} <=> $b->{requested_qty} } 

				
				# Count the net press sheets per form.
				map  { 
					   $_->{'requested_qty1' } = $_->{requested} / 100 * $qtys[0];
					   $_->{'requested_qty2' } = $_->{requested} / 100 * $qtys[1];
					   $_->{'requested_qty3' } = $_->{requested} / 100 * $qtys[2];
					   $_->{requested_qty} = round $_->{requested} / 100 * $qty;
					   $_->{final_qty} = ceil($_->{final} / 100 * $qty);
					   $_ } @{$f} ];

			$form{net_sheets} = ceil(@{$f}[0]->{final_qty} / @{$f}[0]->{slots});


			push @{ $results{FORMS} }, \%form;

		}
	} else { 
		 map {
			$$form_count++;
			push @{$results{FORM_COUNT}}, { id =>  $$form_count } 
		} 1..$results{txtSignatureQuantity};

    }

	if ($multi) {
		my $bookid = eprint::project::get_service_index($log, $dbh, $pid, 'Book');

		my %vspecs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $bookid);

		my @versions = eprint::Service::Book::mp_versions(\%vspecs);

		$results{VERSIONS} = \@versions;
	}

    $results{'NoPrint'} = $results{chargefor} eq 'Free' ? 1 : 0;

    $results{'PaperOut'}     = ceil($results{'hdnSheetQuantity1'} / $results{hdnPaperBuyQuantity1}) if  $results{hdnPaperBuyQuantity1} ;


    $results{'UserType'}     = $userType;
    $results{'ProjectIndex'} = $pid;
    $results{'ServiceIndex'} = $sid;

    return \%results, \@materials;

}

sub ink_mixing {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);
    my @inks;
    my %results;
    my %inkHash;
    my $qty = scalar $dbh->selectrow_array(
        qq{
        SELECT intquantity$qtyIndex 
        FROM tbl_projects
        WHERE lngprojectindex = ?
    }, undef, $pid);
    foreach my $sigIndex (@signature_service_indices) {
        %results = eprint::service::get_specifications_pairs(
            $log, $dbh, undef, $sigIndex,
            "s0_black",
            "s0_process",
            "s0_pms_1_name",
            "s0_pms_2_name",
            "s0_pms_3_name",
            "s0_pms_4_name",
            "s0_pms_5_name",
            "s0_pms_6_name",
            "txtSpecialSideOneColour7",
            "txtSpecialSideOneColour8",

            "s1_black",
            "s1_process",
            "s1_pms_1_name",
            "s1_pms_2_name",
            "s0_pms_3_name",
            "s1_pms_4_name",
            "s1_pms_5_name",
            "s1_pms_6_name",
            "txtSpecialSideTwoColour7",
            "txtSpecialSideTwoColour8",
            "ProjectType",
            "inkQtyPMS1",
            "inkQtyPMS2",
            "inkQtyPMS3",
            "inkQtyPMS4",
            "inkQtyPMS5",
            "inkQtyPMS6",
            "inkQtyPMS7",
            "inkQtyPMS8",);
        for (my $i = 1; $i < 9; $i++) {
            if (($results{"inkQtyPMS$i"})
                && (   ($results{"txtSpecialSideTwoColour$i"})
                    || ($results{"txtSpecialSideOneColour$i"})))
            {
                my $inkqty = $results{"inkQtyPMS$i"};

                if ($inkqty =~ 'e') {
                    my ($base, $power) = split('e', $inkqty);
                    $inkqty = $base**$power;
                }
                $inkqty = $inkqty * $qty;
                $inkHash{$i}{qty} += $inkqty;
                my $name = $results{"txtSpecialSideOneColour$i"};
                $name = $results{"txtSpecialSideTwoColour$i"}
                  if !$name;
                $inkHash{$i}{name} = $name;
            }
        }
    }
    for (my $i = 1; $i < 9; $i++) {
        my $inkqty = $inkHash{$i}{qty};
        if (($inkqty <= .25) && ($inkqty > 0)) {
            $inkqty = .25;
        }
        else {
            $inkqty = (int((($inkqty) * 4) + .5)) / 4;
        }
        if ($inkqty) {

            push @inks,
              { name => $inkHash{$i}{name},
                qty  => $inkqty, };
        }
    }

    $results{inks} = \@inks;
    my @materials;
    for my $ink (@inks) {
        push @materials,
          { name     => $$ink{name},
            qty      => $$ink{qty} . " kg",
            category => 'Inks', };
    }

    return \%results, \@materials;
}

sub imposition_layout {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my %hash;
    my $signatureIndex            = 0;
    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);
    my $multi = eprint::project::is_multipage($log, $dbh, $pid);
    my $firstIndex = $signature_service_indices[0];
    foreach my $index (@signature_service_indices) {
        my %results =
          eprint::service::get_specifications_pairs(
            $log,                   $dbh,
            undef,                  $index,
            "hdnNumRuns",           "txtServiceDescription",
            "txtSignatureQuantity", "txtQuantity",
            "hdnImposition",        "txtImageWidth",
            "txtImageHeight",       "hdnTrap",
            "spreads_in_group",     "bleed_size",
            "bleed_sides",         "spreads_in_group",
			"runstyle",		   "txtSignatureSize"
		  );

		$results{pages} = $results{txtSignatureSize} * $results{spreads_in_group};


        my ($twoQty,      $fourQty,       $sixQty,
            $eightQty,    $twelveQty,     $sixteenQty,
            $twentyQty,   $twentyfourQty, $thirtytwoQty,
            $gateFoldQty, $doubleGateFoldQty)
          = eprint::service::get_specifications(
            $log,                    $dbh,
            undef,                   $index,
            "txtSignatureQty2Page",  "txtSignatureQty4Page",
            "txtSignatureQty6Page",  "txtSignatureQty8Page",
            "txtSignatureQty12Page", "txtSignatureQty16Page",
            "txtSignatureQty20Page", "txtSignatureQty24Page",
            "txtSignatureQty32Page", "txtSignatureQtyGateFolded",
            "txtSignatureQtyDoubleGateFolded",);

        my $sigQty =
          $twoQty + $fourQty + $sixQty + $eightQty + $twelveQty + $sixteenQty +
          $twentyQty + $twentyfourQty + $thirtytwoQty + $gateFoldQty +
          $doubleGateFoldQty;
        if (!(eprint::project::is_multipage($log, $dbh, $pid))) {
            $results{'txtSignatureQuantity'}       = $results{'hdnNumRuns'};
            $results{'txtQuantity'}                = 1;
            $results{'spreads_in_group'}          = $results{'hdnNumRuns'};
            $results{'spreads_in_group'} = 1;
        }
        else {
            $results{txtSignatureQuantity} = $sigQty;
            for my $tmp ("bleed_size",  "chkBleedLeft",
                         "chkBleedRight", "chkBleedTop",
                         "chkBleedBottom")
            {
                if (!$results{$tmp}) {
                    ($results{$tmp}) =
                      eprint::service::get_specifications($log, $dbh, undef,
                                                          $firstIndex, $tmp);
                }
            }
        }
        push @{ $hash{'signature'} }, \%results;
    }

    my $pressType = scalar $dbh->selectrow_array( q{
        SELECT strid
        FROM tbl_equipment_type
        WHERE lngindex = (
            SELECT lngpresstype
            FROM tbl_projects
            WHERE lngprojectindex = ? )
    }, undef, $pid);

	$hash{pressType} = $pressType;

    return \%hash;
}

sub header_info {
    my ($log, $dbh, $pid, $qtyIndex) = @_;

    my $index = eprint::project::get_print_container($log, $dbh, $pid);

    my @signature_service_indices =
      eprint::project::get_signature_indices($log, $dbh, $pid);

    my $signatures = scalar @signature_service_indices; 
    my @colours;
    my %signature_hash;
    my $press     = '';
    my $run_style = '';
    my $forms;

    foreach my $sigIndex (@signature_service_indices) {
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
            $log, $dbh, undef, $sigIndex, @specs
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
        my %specs = eprint::service::get_specifications_pairs(
              $log, $dbh, undef, $sigIndex, qw(hdnPress runstyle side_link imp)
        );

# CUSTOM CODE FOR FLASH
#
    # Retrieve this services imposition information
    my $imp = sthaw(decode_base64($specs{imp}));

	# Std Project qtys from project.pm
    my @qtys = get_quantities($log,  $dbh, $pid);
    my $qty  = $qtys[0];


    if ($imp and (@{$imp->{layout}} > 1 or @{$imp->{layout}[0]} > 1)) {
        # If there's more than one version, list the versions. We don't care
        # what sheet they're on, just the version information.
		my $i;
		foreach my $f (@{ $imp->{layout} }) {
			$i++; # Count the number of Forms

			my %form;
			$form{label} = "Form $i";

			$form{VERSIONS} = [ 
				sort { $a->{label} cmp $b->{label} } 

				# Count the net press sheets per form.
				map  { 
					   $_->{requested_qty} = round $_->{requested} / 100 * $qty;
					   $_->{final_qty} = ceil($_->{final} / 100 * $qty);
					   $_ } @{$f} ];

			$form{net_sheets} = ceil(@{$f}[0]->{final_qty} / @{$f}[0]->{slots});

			push @{ $forms }, \%form;

		}
    }

# END CUSTOM CODE


#        $press = $specs{hdnPress} = eprint::equipment::get_id_by_index($log, $dbh, $specs{hdnPress});

        my $flag = 1;
        for my $key (keys %signature_hash) {
            $flag = 0
              if ($count[0] == $signature_hash{$key}{colour1})
              && ($count[1] == $signature_hash{$key}{colour2})
              && ($text[0]  eq $signature_hash{$key}{side1_info})
              && ($text[1]  eq $signature_hash{$key}{side2_info});
        }
        if ($flag) {
            my $c = {
                colour1    => $count[0],
                colour2    => $count[1],
                side1_info => $text[0],
                side2_info => $text[1], 
            };
			if ( $specs{side_link} ) {
				$c->{colour2} = $c->{colour1};
				$c->{side2_info} = $c->{side1_info};
			}
            push @colours, $c;
            $signature_hash{$sigIndex} = $c;
        }

        # Map the code to a longer name.
        $run_style = $RUN_STYLE{ $specs{runstyle} } . q{ };
    }

    my %hash = get_specifications_pairs($log, $dbh, $pid, $index,
            "final_width",            "final_height",
            "flat_width",             "flat_height",
            "txtTotalPageQuantity",   "txtNameQuantity",
            "rdbCover",               "Interior Spreads",
            "GateFolded Spreads",     "txtInsertQuantity",
            "versions",               "txtPressSheetComboItems",
	    "final_depth", "num_versions"
    );
    $hash{FORMS} = $forms;
	my $mp_versions = eprint::project::mp_versions($pid);
	$hash{num_versions} = $mp_versions if $mp_versions > 1;
	my $prod_versions = $dbh->selectrow_array(q{
		SELECT versions FROM tbl_order_contents WHERE lngprojectindex = ?}, undef, $pid);

	$hash{num_versions} = $prod_versions if $prod_versions;


    @hash{qw(interior_spreads gatefolded_spreads)}
        = @hash{"Interior Spreads", "GateFolded Spreads"};

    @hash{qw(ptype ProjectType)} = get_type($log, $dbh, $pid);

    my %hash2;
	my $ps = project_summary($dbh, $pid);
    %hash2 = %{ $ps } if defined $ps;

    @hash{ keys %hash2 } = values %hash2;

    if ($hash{ptype} eq 'ScreenItem') {
        my %hash3 =
          eprint::service::get_specifications_pairs(
                         $log,
                         $dbh,
                         undef,
                         eprint::project::get_print_container($log, $dbh, $pid),
                         'txtItemWidth',
                         'txtItemHeight',
                         'txtItemDepth',
                         'txtScreenPrintingItemWeight',
                         'txtScreenPrintingSurfaces',);
        @hash{ keys %hash3 } = values %hash3;
    }

    $hash{'runstyle'} = $run_style;
    $hash{'hdnPress'}    = $press;
    $hash{colours}       = \@colours;
    $hash{'multipage'}   = eprint::project::is_multipage($log, $dbh, $pid);
    $hash{txtSignatureQuantity}        = $signatures;
    $hash{txtGateFoldedSpreadQuantity} = 0
      if (!$hash{txtGateFoldedSpreadQuantity});
    $hash{txtInsertQuantity} = 0
      if (!$hash{txtInsertQuantity});
    my ($companyPhone, $sales_rep) =  $dbh->selectrow_array(q{
        SELECT strphone, (SELECT strFirstName || ' ' || strLastName FROM 
							tbl_customer_users WHERE lnguserid = lngsalesperson)
        FROM tbl_customer
        WHERE lngcustomerid =
        (   SELECT lngcustomerid
            FROM tbl_projects
            WHERE lngprojectindex = ?
        )
    }, undef, $pid);
    my ($programs, $other, $icomments) = $dbh->selectrow_array(q{
        SELECT strprograms, strotherprograms, strInvoiceComments 
        FROM tbl_projects
        WHERE lngprojectindex = ?
    }, undef, $pid);

	$hash{InvoiceComments} = $icomments;

    $programs =~ s/;/\,/g;
	$programs .= ' ' . $other if $programs eq 'Other';
    my ($order) = $dbh->selectrow_hashref(
        q{
    SELECT 
		strfirstname,   strlastname, strsalutation,
		strcompanyname, straddress1, straddress2,
		strcity,        strstate,    strpostalcode,
		strcountry,     strponumber, strphone,
		strfax,         strext,      stremail
    FROM tbl_orders
    WHERE lngorderid = 
        ( SELECT lngorderid
          FROM tbl_order_contents
          WHERE lngprojectindex = ? limit 1
        )
    }, undef, $pid);

    $hash{order_id} = scalar $dbh->selectrow_array(
        q{
            SELECT lngorderid
            FROM tbl_order_contents
            WHERE lngprojectindex = ?
        }, undef, $pid);

    $hash{OrderedQuantity} = scalar $dbh->selectrow_array(q{
        SELECT intquantity
        FROM tbl_order_contents
        WHERE lngorderid = ?
		AND lngprojectindex = ?
    }, undef, $hash{order_id}, $pid);

	my $id = $hash{order_id};
	$id =~ /(\d\d\d\d)(\d\d\d\d)/;

    $hash{docket_id}       = "$1  $2-$pid";
    $hash{OrderFirstName}  = $order->{strfirstname};
    $hash{OrderLastName}   = $order->{strlastname};
    $hash{OrderSalutation} = $order->{strsalutation};
	$hash{order}           = $order;
    $hash{phoneNumber}     = $companyPhone;
    $hash{software}        = $programs;
	$hash{SalesRep}		   = $sales_rep;

    {
        no warnings qw(deprecated syntax);
        $hash{txtNameQuantity} =  $hash{num_versions} ? $hash{num_versions} : $hash{versions} ? split(',', $hash{versions})/2 : 1;
    }

	my $ship = $dbh->selectcol_arrayref(q{
		SELECT strname, strvalue FROM tbl_service_specifications
		WHERE  lngserviceindex = ( SELECT lngserviceindex 
								   FROM tbl_service_specifications 
								   WHERE lngprojectindex = ?
								   AND   strname = 'rdbShippingContents'
								   AND   strvalue = 'Project'
								   ORDER BY 1 LIMIT 1)
	}, {Columns=>[1,2]}, $pid);

	my %x = @{$ship};
	$hash{ship} = \%x;

	#Im not sure why we're showing this on the docket instead of strname --
	#since that is, after all, strname's intended purpose.
	$hash{ProjectType} =~ s/^LF_/Large Format /;

	map {
		my ( $n, $v, $val) = $dbh->selectrow_array(q{
			SELECT strname, 
			  ( SELECT strname FROM tbl_materials 
                WHERE strid = tbl_service_specifications.strvalue ),
		strvalue
            FROM tbl_service_specifications 
			WHERE lngprojectindex = ? AND strname = ?
		} , undef, $pid, $_);

        $hash{$n} = $_ eq 'double_sided' ? $val : $v;

	} qw(mounting_type s0_laminate s1_laminate double_sided  );

# Comment this out until it is in production.
#    	$hash{InternalID} = scalar $dbh->selectrow_array( q{
#        	SELECT internalid FROM tbl_projects WHERE lngprojectindex = ?
#    	}, undef, $pid);
	
	$hash{RFQAwardedSupplier} = $dbh->selectrow_array(q{
		SELECT strcompanyname FROM tbl_customer c, rfq r, rfq_supplier rs
		WHERE r.id = rs.rfq AND rs.supplier = c.lngcustomerid
		AND pid = ?
	}, undef, $pid);
	

	$hash{copy_pid} = $dbh->selectrow_array(q{
		SELECT copy_pid FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	$hash{delivery_date} = eprint::employee_project::delivery_date($dbh, $pid);

	$hash{order_pids} = $dbh->selectall_arrayref(q{
		SELECT lngprojectindex as pid 
		FROM tbl_order_contents 
		WHERE lngorderid = ? AND lngprojectindex <> ?
		ORDER by 1;
	}, {Slice => {} }, $hash{order_id}, $pid) if $hash{order_id};

	$hash{bindery_type} = eprint::project::get_bindery_type($log, $dbh, $pid);

    return \%hash;

}


sub fill_info {
    my ($r, $log, $dbh, $pid, $sid, $qtyIndex) = @_;
    my $ref = scalar $dbh->selectrow_array(q{
        SELECT lower(strservicetype)
        FROM tbl_project_contents
        WHERE lngserviceindex = ?
    }, undef, $sid);
    
    my $press_type = scalar $dbh->selectrow_array(q{
        SELECT e.strid
        FROM tbl_equipment_type e, tbl_projects p
        WHERE e.lngindex = p.lngpresstype
          AND p.lngprojectindex = ?
    }, undef, $pid);

    my $html =
      ssi::insert_html($r, "/includes/main/docket/service_type/$ref.html");

    my @subsitutes = ();
    for my $tmp ($html =~ /<\?([\s\w\$\$\(\)\{\}\'->|!&]+)\?>/g) {
        my $flag = 0;
        for my $subTmp ($tmp =~ /variable-?>?{\'?(\w+)\'?}/g) {
            push @subsitutes, $subTmp;
            $flag = 1;
        }
        push @subsitutes, $tmp if !$flag;
    }

    return add_leading_zeros($log,
                        {  eprint::service::get_specifications_pairs(
                              $log, $dbh, undef, $sid, @subsitutes
                           ), sid => $sid
                        });
}

sub add_leading_zeros {
    my ($log, $hash) = @_;
    for my $key (keys %$hash) {
        $hash->{$key} = '0' . $hash->{$key}
          if ($hash->{$key} =~ /^\.\d+/);
    }
    return $hash;
}

use PDF::WebKit;
# This will take a docket and display it as a printer friendly pdf
sub pdf {
  my ($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex) = @_;
  $variable->{is_docket} = 1;
  $pid      ||= $r->param('pid') || $r->param('ProjectIndex');
  $catID    ||= $r->param('Category');
  $qtyIndex ||= $r->param('QuantityIndex') || 1;
  display($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex);
  $variable->{siteURL}  = "http://" . $r->hostname;
  my $page = 'main/proj/proj_docket_printer_friendly.html';
  my $filename = ssi::get_file_path($r, $page);

  my $fh;

  if (!open $fh, '<', $filename ) {
      $dbh->disconnect;
      $r->log_error("Failed opening $page: $!");
      die "Failed to open $filename: $!";
  }

  # read in the data
  my $file_data = do { local $/ = undef; <$fh> };

  close $fh;

  my $html = ssi::variable_substitution(
      $r, $log, $dbh, $file_data, $variable
  );
  my $kit = PDF::WebKit->new(\$html, page_height => '14.33in', page_width => '10.12in');
  my $data = [$kit->to_pdf()];
  $variable->{Download} = 1;
  $variable->{File_Data} = $data;

  return OK;
}


# This procedure is the main procedure which displays the main 'docket'
sub display {
    #catID = -2 when it is sending an email
    #Yes this is ugly, this procedre really should be refactored
    #Will do when I have a chance.
    my ($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex, $is_docket) = @_;

    $pid      ||= $r->param('pid') || $r->param('ProjectIndex');
    $catID    ||= $r->param('Category');
    $qtyIndex ||= $r->param('QuantityIndex') || 1;

if ( $r->param('EditedVersion') ) {
	$dbh->do(q{DELETE FROM docket WHERE pid = ?}, undef, $pid);
	$dbh->do(q{INSERT INTO docket values ( ?, ? ) }, undef, $pid, $r->param('EditedVersion'));
} elsif ( $r->param('resetdocket') ) {
	$dbh->do(q{DELETE FROM docket WHERE pid = ?}, undef, $pid);
}

$variable->{ModifiedDocket} = $dbh->selectrow_array(q{
	SELECT data from docket WHERE pid = ?
}, undef, $pid);

    $variable->{is_docket} = $is_docket; 

    if ( $r->param('InternalID') ) {
        $dbh->do(q{
            UPDATE tbl_projects set internalid = ? WHERE lngprojectindex = ?
        },undef, $r->param('InternalID'), $pid);
    }

    #my $iid = $dbh->selectrow_array(q{
    #    SELECT internalid FROM tbl_projects WHERE lngprojectindex = ?
    #}, undef, $pid );

    return if !$pid;

    #$ssi::INVALID_KEY = 1;

    my $str = q{
                SELECT lngcustomerid, strCompanyName FROM tbl_customer WHERE ysnsupplier = 'Y' order by 2
        };

    if ( $r->param('supplier') ) {
            $dbh->do(q{
                    UPDATE tbl_projects SET supplier = ? WHERE lngprojectindex = ?
            }, undef, $r->param('supplier'), $pid);
    }
    my $s = $dbh->selectrow_array(q{
            SELECT supplier FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

    $$variable{SUPPLIERS} = ssi::fill_drop_down($log, $dbh, $str, $s);

    my $category = setup_categories($log, $dbh, $pid, $variable, 1);


	#Docket for projects that use Custom Sort now have 2 views.
	#IF viewing all services the will be shown in a 'Custom' sort category;
	#IF viewing a single service category i.e. "Packaging", still sort by  Custom sort order but 
	#only show services for that category.	
	my $custom = $dbh->selectrow_array(q{
		SELECT max(custom_sort) from tbl_project_contents WHERE lngprojectindex = ?
	}, undef, $pid);
	
	my $use_custom;
	$use_custom = 1 if $catID == -3 or $catID == 0;

	if ( $use_custom  ) {
		$category = $dbh->prepare(q{ SELECT distinct 1, 'Custom' WHERE ? > 0 });

	}

	my $standard_sort = q{
        SELECT lower(t.strid) AS ref, t.strname AS name , p.lngserviceindex AS ID, t.strid AS strID, p.ysnremoved as supplied
        FROM tbl_service_types t, tbl_project_contents p
        WHERE ( t.strid = p.strservicetype OR (p.strservicetype is null AND (t.strid = 'Printing' OR t.strid='InkMixing' ) ))
        AND p.lngprojectindex = ?
        AND t.strcategory = (SELECT strid FROM tbl_service_categories WHERE lngindex = ?) 
		ORDER by custom_sort
	};

	my $custom_sort_sql = q{
        SELECT lower(t.strid) AS ref, t.strname AS name , p.lngserviceindex AS ID, t.strid AS strID, p.ysnremoved as supplied
        FROM tbl_service_types t, tbl_project_contents p
        WHERE ( t.strid = p.strservicetype OR (p.strservicetype is null AND (t.strid = 'Printing' OR t.strid='InkMixing' ) ))
        AND p.lngprojectindex = ?
		
		ORDER by custom_sort
	
	};

    # Statement to get the service types in a categroy.
    my $service_type;
	my $service_sql = $use_custom ? $custom_sort_sql : $standard_sort;

    $service_type = $dbh->prepare($service_sql);

    $category->execute($pid);
    my %services_by_category;
    my ($id, $name);
    $category->bind_columns(\$id, \$name);

    while ($category->fetch) {
		if ( $use_custom ) {
        	$services_by_category{$name} = $dbh->selectall_arrayref($service_type, { Slice => {} }, $pid);
		} else  {
        	$services_by_category{$name} = $dbh->selectall_arrayref($service_type, { Slice => {} }, $pid, $id);
		}
    }


    my $project_type = scalar $dbh->selectrow_array(q{
        SELECT strid
        FROM tbl_projecttypes
        WHERE lngindex = ( SELECT lngprojecttype
                           FROM tbl_projects
                           WHERE lngprojectindex = ? )
    }, undef, $pid);

    push @{ $services_by_category{'Prepress'} },
      { ref   => 'impositionlayout',
        name  => 'Imposition Layout',
        id    => undef,
        strid => 'Imposition Layout', }
      if ($project_type ne 'ScreenItem');

    push @{ $services_by_category{'Prepress'} },
      { ref   => 'inkmixing',
        name  => 'Ink Mixing',
        id    => undef,
        strid => 'Ink Mixing', };

    if (eprint::project::is_multipage($log, $dbh, $pid)) {
        # The following sorts the additional signatures so they show up in
        # this order: Interior Spreads, Gate Folded Spreads, and Cover.
        my %signatures;
        while (my $hash = shift @{ $services_by_category{Printing} }) {
            if ($hash->{'ref'} eq 'printing') {
                my ($ref) =
                  eprint::service::get_specifications($log, $dbh, undef,
                                          $hash->{id}, "txtServiceDescription");
                $ref =~ /(\w+)\s+\w+/;
                $signatures{$1}{$ref} = $hash;
				$hash->{desc} = $ref;
            }
        }
        my @cover_list    = sort keys %{ $signatures{'Cover'} };
        my @interior_list = sort keys %{ $signatures{'Interior'} };
        my @gate_list     = sort keys %{ $signatures{'GateFolded'} };
        my @surfaces      = sort keys %{ $signatures{'Surfaces'} };

        while (my $value = shift @cover_list) {
            push @{ $services_by_category{Printing} },
              $signatures{Cover}{$value};
        }
        delete $signatures{Cover};

        while (my $value = shift @surfaces) {
            push @{ $services_by_category{Printing} },
              $signatures{Surfaces}{$value};
        }
        delete $signatures{Surfaces};
        while (my $value = shift @interior_list) {
            push @{ $services_by_category{Printing} },
              $signatures{Interior}{$value};
        }
        delete $signatures{Interior};
        while (my $value = shift @gate_list) {
            push @{ $services_by_category{Printing} },
              $signatures{GateFolded}{$value};
        }
        delete $signatures{GateFolded};


        # Now deal with Signatures that have custom References.
        my @others = sort keys %signatures;
        while (my $key = shift @others) {
            my @list = sort keys %{ $signatures{$key} };
            while (my $value = shift @list) {
                unshift @{ $services_by_category{Printing} },
                $signatures{$key}{$value};
            }
        }
    }


	print STDERR "HAVE CAT SERVCIE", Dumper(\%services_by_category);
print STDERR "END DOCKET DISPLAY \n", Dumper($variable->{CategoryMenu});

    setup_docket($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex,
                 \%services_by_category);



}

sub summary_display {

    # This procedure is the main procedure
    # which displays the main 'docket'
    #catID = -2 when it is sending an email
    #Yes this is ugly, this procedre really should be refactored
    #Will do when I have a chance.
    my ($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex) = @_;

    return if !$pid;

    #$ssi::INVALID_KEY = 1;

    my $category = setup_categories($log, $dbh, $pid, $variable);

    # Statement to get the service types in a categroy.
    my $service_type;
    $service_type = $dbh->prepare(
        q{
        SELECT lower(t.strid) AS ref, t.strname AS name , p.lngserviceindex AS ID, t.strid AS strID, p.ysnremoved as supplied
        FROM tbl_service_types t, tbl_project_contents p
        WHERE ( t.strid = p.strservicetype OR (p.strservicetype is null AND (t.strid = 'Printing' OR t.strid='InkMixing' ) ))
            AND p.lngprojectindex = ?
            AND t.strcategory = ?
            AND(t.ysnviewvisible = 'Y' OR t.strid = 'Printing')
    });

    $category->execute($pid);
    my %services_by_category;
    my ($id, $name);
    $category->bind_columns(\$id, \$name);
    while ($category->fetch) {
        $services_by_category{$name} =
          $dbh->selectall_arrayref($service_type, { Slice => {} }, $pid, $name);
    }
    $services_by_category{'Shipping'} =
      [shift @{ $services_by_category{'Shipping'} }];
    eprint::print::display_project($log, $dbh, $variable, $pid);

    setup_docket($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex,
                 \%services_by_category);

    # Done because chris doesn't want additional signatures to show up on
    # quote and order. He just wants printing to show up.
    if (eprint::project::is_multipage($log, $dbh, $pid)) {
        my @printing_services = ();
        for my $tmp (@{ $variable->{categories} }) {
            if ($tmp->{id} eq 'Printing') {
                for my $subTmp (@{ $tmp->{service_type} }) {
                    if ($subTmp->{ref} ne 'additionalsignature') {
                        push @printing_services, $subTmp;
                    }
                }
                push @printing_services,
                  { ref  => 'printing',
                    name => 'Printing', };
                $tmp->{service_type} = \@printing_services;
            }
        }
    }
    return OK;
}

# Gets the Categories for the given service type.
sub setup_categories {
    my ($log, $dbh, $pid, $variable) = @_;
    my $category = $dbh->prepare(q{
        SELECT distinct c.lngindex AS id, c.strname AS name
        FROM tbl_service_categories c, tbl_service_types t, tbl_project_contents p
        WHERE t.strcategory = c.strid
          AND t.strid = p.strservicetype 
          AND p.lngprojectindex = ?
        ORDER BY c.lngindex
    });
    $variable->{CategoryMenu} =
      $dbh->selectall_arrayref($category, { Slice => {} }, $pid);
    return $category;
}

sub setup_docket {
    # Note: Cat = -1 is what displays just materials.  If materials are every
    # added to the database in the same way the services are then this should
    # be changed.
    my ($r, $log, $dbh, $variable, $pid, $catID, $qtyIndex,
        $services_by_category)
      = @_;

    $variable->{ProjectIndex} = $pid;
    if ($catID == -2) {
        $variable->{email} = 1;
    }
    else {
        $variable->{email} = 0;
    }
    $variable->{'multipage'} = eprint::project::is_multipage($log, $dbh, $pid);
    if ($r->param('Summary')) {
        $variable->{summary} = 1;
    }
    else {
        $variable->{summary} = 0;
    }

    #loads the change orders
    $variable->{change_order} = PQS::model::change_order::get_change_order($pid);
    $variable->{parent_change_order} = PQS::model::change_order::get_parent_change_order($pid);

    $variable->{site}       = $r->uri;
    $variable->{dockethash} = undef;
    $variable->{Category}   = $r->param('Category');
    $variable->{Category}   = $catID
      if !$variable->{Category};
    $qtyIndex = $r->param('rdbQtyType')
      if ($qtyIndex == undef);
    my $order_id = $r->param('order_id');
    if ($order_id == undef) {
        $order_id = scalar $dbh->selectrow_array( q{
            SELECT lngorderid
            FROM tbl_order_contents
            WHERE lngprojectindex = ?
        }, undef, $pid);
    }
    $variable->{order_id}  = $order_id;
    $variable->{docket_id} = $order_id . "-" . $pid;
    if ($qtyIndex == undef) {
        $qtyIndex = scalar $dbh->selectrow_array( q{
            SELECT intquantityIndex
            FROM tbl_order_contents
            WHERE lngprojectindex = ?
        }, undef, $pid);
    }
    $variable->{QtyIndex} = $qtyIndex;
    $variable->{"ddmQtyIndex$qtyIndex"} = 'checked="checked"';
    
#    $variable->{InternalID} = scalar $dbh->selectrow_array( q{
#        SELECT internalid FROM tbl_projects WHERE lngprojectindex = ?
#    }, undef, $pid);

    my $pressType = scalar $dbh->selectrow_array( q{
        SELECT strid
        FROM tbl_equipment_type
        WHERE lngindex = (
            SELECT lngpresstype
            FROM tbl_projects
            WHERE lngprojectindex = ? )
    }, undef, $pid);
	$variable->{pressType} = $pressType;
    $variable->{HeaderInfo} = header_info($log, $dbh, $pid);
    $variable->{project} = project_summary($dbh, $pid);
    my @categories;
    my @materials;
	my $form_count;
    for my $cat (map { $_->{name} } @{ $variable->{CategoryMenu} }) {
        my $services = $$services_by_category{$cat};

	

        my $catNumericalID = scalar $dbh->selectrow_array(q{
            SELECT lngindex
            FROM tbl_service_categories
            WHERE strname = ?
        }, undef, $cat);
        if (($catID == undef) || ($catNumericalID == $catID) || ($catID == -1) || $catID == -3) {
	
	  #Collect the material information for ALL services when viewing the 'Other' category
	  if ( $catID == -3 ) {

            foreach my $service (@$services) {
                my ($ref, $name, $id, $supplied, $desc) 
                    = @$service{qw(ref name id supplied desc)};

                    my ($data, $material) =
                      	summary($r, $log, $dbh, $pid, $id, $qtyIndex, $name, \$form_count);

			
			for my $m (@{$material}) {
			    push @materials, $m;
			}
		}
	  }

	  next if $catID == -3 && $cat eq 'Prepress';
	  next if $catID == -3 && $cat eq 'Printing';

            my @service_types;
            my @supplied_service_types;

            foreach my $service (@$services) {
                my ($ref, $name, $id, $supplied, $desc) 
                    = @$service{qw(ref name id supplied desc)};


                next if ($ref eq 'inkmixing' && $cat eq 'Printing');

                my ($filename, $data, $material);
                eval {
                    $filename = "/includes/main/docket/service_type/$ref.html";

                    # Get the service information.
                    ($data, $material) =
                      summary($r, $log, $dbh, $pid, $id, $qtyIndex, $name, \$form_count);
                };

				$data->{is_docket} = $variable->{is_docket};

                # If there's an error we'll set the file to include to our
                # error filler and pass the service name to it. Not very good
                # handling but better than nothing.
                if ($@) {
                    $filename = "/includes/main/docket/service_type_error.html";
                    $data     = { name => $name, reason => $@, };
                }


                next if $ref eq 'inkmixing' and not @$material;
                next if $ref eq 'custom'    and     $data->{hide_docket};
                
                my $template = ssi::insert_html($r, $filename);

                # Don't process the service if it doesn't have a file. NOTE:
                # We can't just do an existance check as there are multiple
                # rules for where templates can be.
                next if $template =~ /^Could not open/i;


                my $qty       = get_quantity($log,  $dbh, $pid, $id, $qtyIndex);
                my $equipment = get_equipment($log, $dbh, $pid, $id, $qtyIndex);

                my ($comment, $trackingnumber) = $dbh->selectrow_array(q{
                    SELECT strComments, trackingnumber
                    FROM tbl_project_contents
                    WHERE lngserviceindex = ?
                      AND lngprojectindex =?
                }, undef, $id, $pid);

				# Imposition Comments are stored with the project.
				if ( $ref eq 'impositionlayout' ) {
					$comment = $dbh->selectrow_array(q{
						SELECT impcomment FROM tbl_projects WHERE lngprojectindex = ?
					}, undef, $pid);
				}

                $data->{'summary'}  = $variable->{'summary'};
                $data->{'UserType'} = $variable->{'user_type'};
                $data->{'is_staff'} = $variable->{'is_staff'};
				$data->{'ProjectType'} = $variable->{HeaderInfo}{'ProjectType'};
				$data->{'desc'} = $desc || $data->{'ProjectType'};

                $data->{'comment'}  = $comment;
                $data->{'trackingnumber'}  = $trackingnumber;
                $data->{'qtyIndex'} = $qtyIndex;

				# Set the Custom Stock Flag if any of the stock
				# is customer supplied. See Bug 2851.
				$variable->{stock_supplied} = 1 if $data->{stock_supplied};
				$variable->{stock_custom}   = $data->{stock_custom} if $data->{stock_supplied};

                for my $m (@{$material}) {
                    push @materials, $m;
                }

                $data->{mat_usage} = PQS::model::service::get_material_usage($id);
                @{$data->{mat_usage}} = grep {$_->{qty_index} == $qtyIndex} @{$data->{mat_usage}};
                foreach my $mat (@{$data->{mat_usage}}) {
                  $mat->{mat} = PQS::model::materials::material_by_id($mat->{mid});
                }

                $data->{ws_Colour} = $variable->{ws_Colour};

                my $html = ssi::variable_substitution($r, $log, $dbh,
                    $template, $data
                );
                
                # Add Time Data to All Services.
                if ( DISPLAY_TIME_DATA ) {
                    $html .= ssi::variable_substitution($r, $log, $dbh,
                            ssi::insert_html($r, '/includes/main/docket/time.html'), $data
                    );
                }

				#format commments to show line breaks from text area input.
				$comment =~ s/\r/<br>/g; 

		next if $catID == -3 && $cat eq 'Printing';

                if ($supplied) {
                    push @supplied_service_types,
                      { ref       => $ref,
                        name      => $name,
                        qty       => $qty,
                        equipment => $equipment,
                        sid       => $id,
                        comment   => $comment,
                        trackingnumber   => $trackingnumber,
                        html      => $html, };
                }
                else {
                    push @service_types,
                      { ref       => $ref,
                        name      => $name,
                        qty       => $qty,
                        equipment => $equipment,
                        sid       => $id,
                        comment   => $comment,
                        trackingnumber   => $trackingnumber,
                        html      => $html, }
                }

                if ($variable->{dockethash}{$name}) {
                    $variable->{dockethash}{$name}{html} =
                      $variable->{dockethash}{$name}{html} . '<br />' . $html;
                }
                else {
                    $variable->{dockethash}{$name}{html} = $html;
                }
                $variable->{dockethash}{$name}{comment} = $comment;
            }

            push @categories,
              { id                    => $cat,
                name                  => $cat,
                service_type          => \@service_types,
                supplied_service_type => \@supplied_service_types, };
        }
    }
    materials($log, $variable, @materials);

	$variable->{matcomment} = $dbh->selectrow_array(q{
		select papercomment from tbl_projects where lngprojectindex = ?
	}, undef, $pid);

    # Adds Materials to the category menu.
    push @{ $variable->{CategoryMenu} },
      { name => 'Materials',
        id   => '-1', };

    # Allow the template to see the categories and service types.
    $variable->{categories} = \@categories;

    # Load the project summary header into the special $variable variable.
    $variable->{OrderedQuantity} = $variable->{project}{"qty$qtyIndex"};
	
    $variable->{linescreen}  = $dbh->selectrow_array(q{SELECT linescreen FROM tbl_projects WHERE lngprojectindex = ?}, undef, $pid);
    $variable->{certified}   = $dbh->selectrow_array(q{SELECT strvalue FROM tbl_service_specifications WHERE lngprojectindex = ? AND strname = 'certified' LIMIT 1}, undef, $pid);
    $variable->{secureprint} = $dbh->selectrow_array(q{SELECT strvalue FROM tbl_service_specifications WHERE lngprojectindex = ? AND strname = 'secureprint' LIMIT 1}, undef, $pid);

    return OK;
}

sub materials {

    # Sorts the materials and totals the qty of
    # of any material in the same category with
    # the same name.
    my ($log, $variable, @materials) = @_;
    my %materialsHash;
    for my $mat (@materials) {
        push @{ $materialsHash{ $$mat{category} } }, $mat;
    }


    for my $key (keys %materialsHash) {
        my %tmpHash;
        my %tmpHash1;

        if ($key eq 'Inks') {
            push @{ $variable->{materials} },
              { category     => $key,
                subMaterials => \@{ $materialsHash{$key} }, };
        }
        else {

            for my $mat (@{ $materialsHash{$key} }) {
                $tmpHash{ $$mat{name} } += $$mat{qty};
                $tmpHash1{ $$mat{name} } = $mat;
            }

            my @tmpArray;
            for my $subKey (keys %tmpHash) {
                push @tmpArray,
                  { name => $subKey,
                    alt_name => $tmpHash1{$subKey}{alt_name},
                    qty  => $tmpHash{$subKey}, };
            }
            push @{ $variable->{materials} },
              { category     => $key,
                subMaterials => \@tmpArray, 
				comment => 'xyz',
			};
        }
    }
}

sub project_summary {
    my $dbh = shift;
    my $pid = shift;    # Project ID
    return $dbh->selectrow_hashref(q{
        SELECT lngprojectindex     AS id,
               strprojectreference AS reference,
               strcomments         AS comments,
               strStatus           AS status,
               strDesign           AS design,

               -- Quoted quantities
               intQuantity1        AS qty1,
               intQuantity2        AS qty2, 
               intQuantity3        AS qty3,
			   ( SELECT strFirstname || ' ' || strlastname
			     FROM   tbl_customer_users 
				 WHERE  lnguserid = tbl_projects.lnguserindex
			   ) AS user, 

               ( SELECT to_char(daterequired, 'YYYY-MM-DD')
                 FROM tbl_order_contents
         		 WHERE lngprojectindex = ? limit 1
        	   )AS date_required, 

               to_char(dtmcreationdate, 'YYYY-MM-DD') AS date_created, 

               -- Contact Information
               ( SELECT strCompanyName 
                 FROM tbl_Customer 
                 WHERE tbl_customer.lngcustomerID = tbl_Projects.lngcustomerID ) AS company

        FROM tbl_Projects 
        WHERE lngProjectIndex = ?
    }, undef, $pid, $pid);
}

1;

