package eprint::rfq;
use strict;


use ssi     qw( get_dates );

use Data::Dumper;
use eprint::project qw(:common);
use eprint::service qw(:common);
use MIME::QuotedPrint;


#use Test::More tests => 12;
#use Test::PQS::Mechanize;
#use Test::Project qw(cmp_page_to_pricing);


sub api_new_project {
	my ($dbh, $mech, $pid ) = @_;



	my $specs = $dbh->selectrow_hashref(q{
		SELECT 	strdesign as format, 
				strid as rdbPressType,
				lngprojecttype as rdbProjectType,	
				strprojectreference as txtProjectReference,
				intquantity1 as txtQuantity1,
				intquantity2 as txtQuantity2,
				intquantity3 as txtQuantity3,
				strprograms  as format
		FROM tbl_projects p , tbl_equipment_type e
		WHERE lngprojectindex = ?
		AND p.lngpresstype = e.lngindex
	},undef,$pid);


# Must check 
	my $services = $dbh->selectcol_arrayref(q{
		SELECT strservicetype FROM tbl_project_contents
		WHERE lngprojectindex = ?
	}, undef, $pid);

#print STDERR "SERVICES " , Dumper($services);
#	my @forms = $mech->forms();
#	my $f1 = $forms[1];

#	foreach my $i ( @{$f1->{inputs}} ) {
#		next unless $i->{name} eq 'project_service';
#		my $val =  $i->{menu}[1]->{value};
#		$i->check if $services->{$val};
#	}

#print STDERR "CONTENT " , $mech->content;
				
	# Projects - Create Project
	$mech->submit_ok(
    'f1',
    {   format              => { type => 'selectone', value => $specs->{format} },
        rdbPressType        => { type => 'radio',     value => $specs->{rdbpresstype} },
        rdbProjectType      => { type => 'radio',     value => $specs->{rdbprojecttype} },
        txtProjectReference => { type => 'text',      value => $specs->{txtprojectreference} },
        txtQuantity1        => { type => 'text',      value => $specs->{txtquantity1} },
        txtQuantity2        => { type => 'text',      value => $specs->{txtquantity2} },
        txtQuantity3        => { type => 'text',      value => $specs->{txtquantity3} },
        project_service     => { type => 'checkbox',  value => $services },
    }
	);

}
sub api_printing_service {
	my ($dbh, $mech, $sid ) = @_;
print STDERR "API Printing Service \n";

	my $specs = $dbh->selectall_hashref(q{
		SELECT strname, strvalue
		FROM tbl_service_specifications
		WHERE lngserviceindex = ? AND ui_spec
	},'strname',{},$sid);


# Projects - Printing - Brochures / Sell Sheets

my $fields =  {   
		bleed_sides => { type => 'checkbox' },
        bleed_size  => { type => 'selectone' },
        colour_bar  => { type => 'checkbox' },
        ddmColourMatch    => { type => 'selectone' },
        final_height      => { type => 'text' },
        final_width       => { type => 'text' },
        flat_height       => { type => 'text' },
        flat_width        => { type => 'text' },
        override_press    => { type => 'checkbox' },
        override_runstyle => { type => 'checkbox' },
        press             => { type => 'selectone' },
#        project_size      => { type => 'selectone' },
        runstyle          => { type => 'selectone' },
        s0_process        => { type => 'checkbox' },
        s1_process        => { type => 'checkbox' },
        stock_colour      => { type => 'selectone' },
        stock_finish      => { type => 'selectone' },
        stock_name        => { type => 'selectone' },
        stock_weight      => { type => 'selectone' },
        template          => { type => 'radio' },
    };
	map {$fields->{$_}->{value} = $specs->{$_}->{strvalue}} keys %$fields;

	$mech->submit_ok( 'f1',$fields);

}


sub api_bid {
	my ($r, $dbh, $var, $sup, $rid, $pid ) = @_;

	$pid = $r->param('pid') unless $pid;
	$sup = $r->param('sup_id') unless $sup;
	$rid = $r->param('rid') unless $rid;

	$var->{pid} = $pid;
	return unless $pid;



	my ($user, $pass, $url) = $dbh->selectrow_array(q{
		SELECT api_user, api_password, api_url FROM tbl_customer
		WHERE lngcustomerid = ?
	}, undef, $sup);

#	my $mech = Test::PQS::Mechanize->new();

#	$mech->login_api($user,$pass,$url);

#	$mech->create_ok($url.'/main/proj/create.html', undef, 'get create page');


	return;

#	api_new_project( $dbh, $mech, $pid );


#	my $print_services = $dbh->selectrow_arrayref(q{
#		SELECT lngserviceindex FROM tbl_project_contents 
#		WHERE lngprojectindex = ? AND strservicetype = 'Printing'
#	},undef, $pid);

#	map { api_printing_service( $dbh, $mech, $_ ) } @{$print_services};

#	my @forms = $mech->forms();
#	my $f1 = $forms[1];

#	my $api_pid;
#	foreach my $i ( @{$f1->{inputs}} ) {
#		next unless $i->{name} eq 'ProjectIndex';
#		$api_pid =  $i->{value};

#	}



# 	my $p = Project::Pricing->new($mech->content);
#	my $services = $dbh->selectall_hashref(q{
#		SELECT strname, sid 
#		FROM tbl_service_types s, tbl_project_contents pc, rfq_services r
#		WHERE r.rid = ?
#		AND s.strid = pc.strservicetype AND pc.lngserviceindex = r.sid
#	}, 'strname',{}, $rid );
	

#	my $ins = $dbh->prepare(q{
#		INSERT INTO rfq_response values ( ?, ?, ?, ?, ?, ?, Null, ? );
#	});

#	my $stock = $dbh->prepare(q{
#		INSERT INTO rfq_response values ( ?, 12, ?, ?, ?, ?, Null, ? );
#	});

#	map { 
#			my $name = $_->{name};
#			$name = 'Printing' if $name =~ /Press/;
#			print STDERR "CHECKING SERVICE : $name \n";
#			$ins->execute($rid, $services->{$name}->{sid}, $sup, @{$_->{prices}}, $api_pid)   
#		    if $services->{$name};	
#	} @{$p->{pricing}{services}};
#
#	$stock->execute($rid, $sup, @{$p->{pricing}{stock}}, $api_pid)   

}


sub process_rfq {
   my ($r, $log, $dbh, $var, $spo) = @_;
   my $rid = $r->param('rid');
   my $sup_id = $r->param('sup_id') || $var->{user}{company}{id};

my @p = $r->param();
print STDERR "PROCESS RFQ: $rid - @p \n\n";

	if ( $r->param('MakePO') eq 'Auto' ) {
		# Coming from the Make Po Button on the project view page
		# Lookup the rid, sup_id here instead of adding more work
		# to the project view page.

		($rid, $sup_id) = $dbh->selectrow_array(q{
			SELECT rfq, supplier FROM rfq_supplier, rfq
			WHERE rfq.id = rfq_supplier.rfq 
			AND pid = ? ORDER BY rfq DESC LIMIT 1
		}, undef, $r->param('pid'));


	}

   $rid = eprint::rfq::create_rfq( $r, $dbh ) unless $rid;

	if ( $r->param('btnFunction') eq 'Save' ) {

   		save_rfq($r, $dbh, $rid, $sup_id, $var->{user}{id});

	} elsif ( $r->param('AwardRfq') ) {

		award_bid($r, $dbh, $r->param('AwardRfq'), $r->param('rid'), $r->param('sup_id'));

	} elsif ( $r->param('MakePO') ) {
		#Can now make PO from rfq page, rfq_waiting email or project view page.



		$var->{is_po} = 1;

		make_po($r, $dbh, $r->param('MakePO'), $rid, $sup_id);

		$var->{user_select} = $dbh->selectall_arrayref(q{
			SELECT lnguserid, strFirstName || ' ' || strLastname as name, stremail 
			FROM tbl_customer_users WHERE lngcustomerid = ?
			AND ysnaccountactivation = 'Y'
		}, {Slice=>{}}, $sup_id);

	} elsif ( $r->param('CancelPO') ) {
		cancel_po($r, $dbh, $r->param('rid'), $r->param('sup_id'));
	}


   load_rfq($r, $log, $dbh, $var, $rid, undef, $sup_id);
print STDERR "HAVE RFQ: ", Dumper($var->{RFQ_Header});

	unless ( $var->{RFQ_Header}{read_date} ) {

		if ( $spo ) {
			$dbh->do("UPDATE rfq SET read_date = NOW() WHERE id = $rid");
		}
	}
	
	my $pid = $dbh->selectrow_array(q{
		SELECT pid from rfq where id = ?
	}, undef, $rid);
print STDERR "HAVE PID FROM RFQ: $rid -- $pid \n";

	$var->{proof_only} =  $dbh->selectrow_array(q{
		SELECT count(approval_prepress) FROM project_files 
		WHERE pid = ?
		AND   approval_prepress   IS NOT NULL 
		AND   approval_production IS NULL
	}, undef, $pid);


   $var->{spo} = $spo;
   $var->{is_po} = 1 if $spo;
   $var->{pid} = $r->param('pid');

}

sub display_rfq {
   my ($r, $dbh, $var) = @_;
   my $rid = $r->param('rid');
   my $pid = $dbh->selectrow_array(q{
        SELECT pid FROM rfq WHERE id = ?
   },undef, $rid);

   if ( $r->param('save_rfq') ) {
        save_rfq($r, $dbh, $rid, $var->{user}{company}{id}, $var->{user}{id});
   } 

   load_rfq($r, $r->log, $dbh, $var, $rid, $pid, $var->{user}{company}{id});

   $var->{supplier} = $var->{user}{company}{id};

}

sub save_rfq {
    my ($r, $dbh, $rid, $sup, $uid) = @_;

    my $to = $dbh->selectrow_array(q{
        SELECT total_only FROM rfq WHERE id = ?
    }, undef, $rid);

	$to = 1;

    if ( $to ) {

    $dbh->do(qq{DELETE FROM rfq_response WHERE rid = $rid AND supplier = $sup});


    my $prices = $dbh->prepare(q{ INSERT INTO rfq_response VALUES ( ?, ?, ?, ?, ?, ?) });
    my $hist  =  $dbh->prepare(q{ INSERT INTO bid_history  VALUES ( ?, ?, ?, ?, ?, ?, ?) });
    my $scom   = $dbh->prepare(q{ UPDATE rfq_supplier SET comments = ? WHERE rfq = ? AND supplier = ? });
    my $stock  = $dbh->prepare(q{ UPDATE rfq_supplier SET exact_stock = ? WHERE rfq = ? AND supplier = ? });
    my $total  = $dbh->prepare(q{ UPDATE rfq SET
        price1 = (SELECT SUM(price1) FROM rfq_response WHERE rid = ?),
        price2 = (SELECT SUM(price2) FROM rfq_response WHERE rid = ?),
        price3 = (SELECT SUM(price3) FROM rfq_response WHERE rid = ?)
        WHERE id = ?
    });
    
    $scom->execute($r->param('RFQSupplierComments'), $rid, $sup) 
        if $r->param('RFQSupplierComments');

    $stock->execute($r->param('stock'), $rid, $sup) 
        if $r->param('stock');

    foreach my $p ( $r->param() ) {
        if ( $p =~ /price_input-(\d*)/ ) {
print STDERR "SAVING RFQ - $p \n\n";
            my @p;
            $p[0] = $r->param("price1-$1") || 0;
            $p[1] = $r->param("price2-$1") || 0;
            $p[2] = $r->param("price3-$1") || 0;
            $prices->execute($rid, $1, $sup, @p);
            $hist->execute($rid, $1, $sup, @p, $uid);
        }
    }
    $total->execute($rid, $rid, $rid, $rid);
    
    }


	my $var = {rid => $rid};
	my $log = $r->log;
    my $email_template = misc::load_file($r, '/email/email_template.html');

    $var->{'ReplacementText'} = "<!--#include virtual=\"/email/content/rfq_response_notification.html\"-->";
	$var->{pid} = $r->param('pid');
	$var->{siteURL} = "http://" . $r->hostname;

    $_ = encode_qp(
        ssi::variable_substitution($r, $log, $dbh, $email_template, $var));

    my @body = ('', $_, 'text/html', 'quoted-printable');

	my ($to) = $dbh->selectrow_array(q{
		SELECT stremail FROM tbl_Customer_Users, rfq WHERE lnguserid = creator
		AND rfq.id = ?
	}, undef, $rid);

 print STDERR "SENDING MAIL TO : $to \n";


	
    my %mail = (
          SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          BCC      => $to,
          SUBJECT => "RFQ Response",);
    misc::send_email_with_attachment($r, $log, \%mail, @body);

	
}


sub load_rfq {

   my ($r, $log, $dbh, $variable, $rid, $pid, $sup_id) = @_;


    $pid = $r->param('pid') || $r->param('ProjectIndex') unless $pid;

    my @servicesIDs = $r->param('rfq');
print STDERR  "HAVE RID: $rid \n";

    @servicesIDs =  @{$dbh->selectcol_arrayref(q{
         SELECT sid FROM rfq_services WHERE rid = ? order by id
    },{},$rid)} unless @servicesIDs;

    my ($qtyIndex, $qty) = $dbh->selectrow_array(q{
        SELECT intquantityIndex, intquantity
        FROM tbl_order_contents
        WHERE lngprojectindex = ?
    }, undef, $pid);
    return if !$pid;

    my $service_type = $dbh->prepare(q{
        SELECT lower(t.strid) AS ref, t.strname AS name , 
               p.lngserviceindex AS ID, t.strid AS strID
        FROM tbl_service_types t, tbl_project_contents p
        WHERE    ( t.strid = p.strservicetype 
              OR (p.strservicetype is null AND t.strid = 'Printing' ))
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

	$variable->{bid_accepted} = scalar $dbh->selectrow_array(q{
		SELECT accepted FROM rfq_supplier where rfq = ? and supplier = ?
	}, undef, $rid, $sup_id); 

	$variable->{__FillInForm}{stock} = scalar $dbh->selectrow_array(q{
		SELECT exact_stock FROM rfq_supplier where rfq = ? and supplier = ?
	}, undef, $rid, $sup_id); 

	my $id = join(',',@servicesIDs); 

	my $api_pid = scalar $dbh->selectrow_array(qq{
		SELECT api_pid FROM rfq_response WHERE rid = ? AND supplier = ? 
		AND api_pid IS NOT NULL AND SID IN ( $id ) LIMIT 1;
	}, undef, $rid, $sup_id);

	my $api_url = scalar $dbh->selectrow_array(q{
		SELECT api_url FROM tbl_customer WHERE lngcustomerid = ?
	}, undef, $sup_id);

	$variable->{api_url} = $api_url . "/main/proj/proj_docket.html?pid=$api_pid" if $api_url && $api_pid;


    for my $sid (@servicesIDs) {
        $tmp =
          $dbh->selectall_arrayref($service_type, { Slice => {} },
                                   $pid, $sid);

print STDERR "LOOKUP UP RFQ SERVCIE: $sid, $pid \n", Dumper($tmp);

        $tmp = shift @$tmp;
        my $qty       = eprint::docket::get_quantity($log,  $dbh, $pid, $sid, $qtyIndex);
        my $equipment = eprint::docket::get_equipment($log, $dbh, $pid, $sid, $qtyIndex);
        my $comment = scalar $dbh->selectrow_array(q{
            SELECT strComments
            FROM tbl_project_contents
            WHERE lngserviceindex = ?
            AND lngprojectindex =?
        }, undef, $sid, $pid);

        my @prices = $dbh->selectrow_array(q{
            SELECT 0, price1, price2, price3 FROM rfq_response 
            WHERE rid = ? AND supplier = ? AND sid = ?
        }, undef, $rid, $sup_id, $sid );


        my ($data, $material) =
          eprint::docket::summary($r, $log, $dbh, $pid, $sid, $qtyIndex, $tmp->{'name'});
        
        push @materials, $_ for @{$material};

        push @services, { 
            ref       => $tmp->{'ref'},
            name      => $tmp->{'name'},
            qty       => $qty,
            equipment => $equipment,
            sid       => $sid,
            comment   => $comment,
	    	prices	  => \@prices,
            html      => ssi::variable_substitution($r, $log, $dbh,
                            ssi::insert_html($r, "/includes/main/rfq/service_type/" . $tmp->{'ref'} . ".html"),
                            $data
                        )# . $inputs 
        };
		delete $printids->{$sid};
    }

	# Get Material Information For any Print Services that were
	# not part of the RFQ Services.
	map { my ($d, $m) = eprint::docket::summary($r, $log, $dbh, $pid, $_, $qtyIndex, 'Printing'); 
	      push @materials, @{$m} 
		} keys %{$printids};

    eprint::docket::materials($log, $variable, @materials);

    my @suppliers;
    $tmp = $dbh->selectall_arrayref(q{
        SELECT lngcustomerid , strcompanyname
        FROM tbl_customer
        WHERE ysnsupplier = 'Y'
		ORDER BY strcompanyname
    }, undef,);

    for my $supplier (@$tmp) {
        push @suppliers, shift @$supplier;
        push @suppliers, shift @$supplier;
    }

    my @totals = $dbh->selectrow_array(q{
        SELECT 0, sum(price1), sum(price2), sum(price3) FROM rfq_response
        WHERE rid = ? AND supplier = ?
    }, undef, $rid, $sup_id );

    $variable->{stock_prices} = $dbh->selectrow_arrayref(q{
           SELECT 0, price1, price2, price3 FROM rfq_response 
           WHERE rid = ? AND supplier = ? AND sid = ?
    }, undef, $rid, $sup_id, 12 );


    $variable->{totals} = \@totals;



    $variable->{Suppliers}     = ssi::make_drop_down(\@suppliers);
    $variable->{administrator} = $variable->{user}{name};
    $variable->{rid} = $rid;
    $variable->{show_rid} = $r->param('rid');
    $variable->{pid} = $pid;
    $variable->{sup_id} = $sup_id;

    my @date = gmtime;
    $variable->{rfq}{date_created} =
      ($date[5] + 1900) . '-' . $date[4] . '-' . $date[3];
    $variable->{QtyIndex}        = $qtyIndex;
    $variable->{ProjectIndex}    = $pid;
    $variable->{RFQ}             = \@services;
#print STDERR "SERVICES: ", Dumper(\@services);
    $variable->{HeaderInfo}      = eprint::docket::header_info($log, $dbh, $pid);
    $variable->{RFQ_Header}             = rfq_header($dbh, $rid, $sup_id);
    $variable->{OrderedQuantity} = $qty;
    $variable->{order_id}  = $r->param('order_id');
 	$variable->{qtys} = [undef, get_quantities($log, $dbh, $pid)];
    $variable->{docketcss} =
      ssi::insert_html($r, "site_specific/styles/docket.css");
    $variable->{admincss} =
      ssi::insert_html($r, "site_specific/styles/administrator.css");

	$variable->{qtys}[1] = undef if ($qty && $qty != $variable->{qtys}[1]);
	$variable->{qtys}[2] = undef if ($qty && $qty != $variable->{qtys}[2]);
	$variable->{qtys}[3] = undef if ($qty && $qty != $variable->{qtys}[3]);

	$variable->{__FillInForm}{closing_time} = $variable->{RFQ_Header}{closing_time};

	my $closing = $variable->{RFQ_Header}{closing_date} . ' ' . $variable->{RFQ_Header}{closing_time};

	
	$variable->{open} = $dbh->selectrow_array(qq{
		SELECT now() < '$closing' 
	}) if $variable->{RFQ_Header}{closing_time};
	$variable->{is_cancelled} = 1 if $variable->{RFQ_Header}{status} eq 'Cancelled';



}


sub rfq_header {
    my ($dbh, $rid, $sup_id) = @_;
    my $head = $dbh->selectrow_hashref(q{
        SELECT 	to_char(closing_date, 'mm/dd/yyyy') as closing_date,
		to_char(supply_date,  'mm/dd/yyyy') as supply_date,
		to_char(send_date,    'mm/dd/yyyy') as send_date,
		to_char(po_date,    'mm/dd/yyyy') as po_date,
		creator, status, comments, po as po_id, closing_time,
		to_char(read_date, 'mm/dd/yyyy') as read_date
        FROM rfq WHERE id = ? 
    }, undef , $rid );

	$head->{supply_date} = 'TBD' unless $head->{supply_date};
    $head->{services} = rfq_services($dbh, $rid);

	$head->{scomments} = $dbh->selectrow_array(q{
		SELECT comments FROM rfq_supplier WHERE rfq = ? AND supplier = ?
	},undef, $rid, $sup_id ) if $sup_id;

	$head->{cancel_comments} = $dbh->selectrow_array(q{
		SELECT cancel_comments FROM rfq WHERE id = ?
	},undef, $rid) if $rid;

	$head->{supplier_name} = $dbh->selectrow_array(q{
		SELECT strCompanyName FROM tbl_customer, rfq_supplier WHERE lngcustomerid =  supplier
		AND rfq = ? AND accepted = true
	}, undef, $rid);
print STDERR "RFQ HEADER $sup_id : $head->{supplier_name} \n";

    return $head;

}

sub rfq_services {
    my ( $dbh, $rid ) = @_;
    return join(', ', @{$dbh->selectcol_arrayref(q{
        SELECT  strname
        FROM    tbl_project_contents pc, rfq_services rs, tbl_service_types st
        WHERE   pc.lngserviceindex = rs.sid 
        AND     st.strid = pc.strservicetype
        AND     rs.rid = ?
    }, undef, $rid )} );
}


sub rfq_project_list {
    my ($r, $dbh, $variable) = @_;

    get_dates($r, $r->log, $dbh, $variable);

    my @params = ();
    my $clause = '';



    my $sql = q{
        SELECT  lngprojectindex as pid,             
                lngcustomerid as cust_id,
                ( SELECT strcompanyname FROM tbl_customer c 
                  WHERE  c.lngcustomerid = p.lngcustomerid   ) as cust_name,
                strprojectreference as ref,
                strstatus as status,
                ( SELECT daterequired FROM tbl_order_contents o
                  WHERE o.lngprojectindex = p.lngprojectindex LIMIT 1 )::date as due_date,

                ( SELECT COUNT(*) FROM rfq WHERE rfq.pid = p.lngprojectindex ) as rfq_sent,

                ( SELECT CASE WHEN ( SELECT COUNT(*) FROM rfq 
                                     WHERE rfq.pid = p.lngprojectindex 
                                     AND closing_date > NOW() ) > 0
                  THEN 'Open'
                  ELSE 'Closed'
                  END ) as rfq_status
        FROM tbl_projects p
        WHERE 1>0
    };

    $sql .= " AND Exists ( SELECT * FROM rfq r, rfq_supplier s WHERE r.id = s.rfq 
								 AND r.pid = p.lngprojectindex 
								 AND s.supplier = $variable->{cust_id} )"
    if $variable->{user_type} eq 'C';

       

 print STDERR "STATUS EQ Unordered : " . $r->param('ddmStatus') . " \n\n";

    if ( $r->param('ddmStatus') eq 'Quoted' ) {
        $clause .= q{
            AND EXISTS ( SELECT lngprojectindex FROM tbl_quote_details q
                         WHERE q.lngprojectindex = p.lngprojectindex ) 
        };
    } elsif ( $r->param('ddmStatus') eq 'Ordered' ) {
        $clause .= q{
            AND EXISTS ( SELECT lngprojectindex FROM tbl_order_contents o
                         WHERE o.lngprojectindex = p.lngprojectindex ) 
        };

    } elsif( $r->param('ddmStatus') ) { 
        $clause .= ' AND strstatus = ?';
        push @params, $r->param('ddmStatus');

    };

    push @params, $variable->{StartDate}, $variable->{EndDate};
    $clause .= ' AND dtmcreationdate BETWEEN ? AND ? ';
       

    if ( $r->param('ddmCustomer') ) {
        $clause .= ' AND  lngcustomerid = ?';
        push @params, $r->param('ddmCustomer');
    }

    $sql .=  $clause;
    $sql .= ' Order By pid ';

print STDERR "HAVE rfQ SQL: $sql " , Dumper(@params);


    my $rfqs = $dbh->selectall_hashref($sql, 'pid',undef, @params);

    my @rfq;
    my %cl;
    my @cust_list;

    my $s = [ sort { $a <=> $b } keys %{$rfqs} ];

    map { push @rfq , $rfqs->{$_}; $cl{$rfqs->{$_}{cust_id}} = $rfqs->{$_}{cust_name} } @{$s};

#	print STDERR "RFQS ", Dumper(@rfq);
	@rfq = grep {$_->{rfq_status} eq $r->param('ddmRFQStatus')} @rfq if $r->param('ddmRFQStatus') ne '';

    $variable->{projects} = \@rfq;

#    map { push @cust_list, $_, $cl{$_} } keys %cl; 
    

#    $variable->{ddmCustomer} = ssi::make_drop_down( \@cust_list, $r->param('ddmCustomer') );

    my $cust_sql = q{ SELECT lngcustomerid, strcompanyname FROM tbl_customer };

    $variable->{ddmCustomer} = ssi::fill_drop_down( $r->log, $dbh, $cust_sql, $r->param('ddmCustomer') );

    $variable->{'ddmStatus'.$r->param('ddmStatus')} = 'selected';
    $variable->{'ddmRFQStatus'.$r->param('ddmRFQStatus')} = 'selected';


    return;
}
sub list_rfqs {
    my ($r, $dbh, $variable, $sup, $pid ) = @_;

    get_dates($r, $r->log, $dbh, $variable);

    my @params;


    my $clause = '';


    my $sql = q{
        SELECT  id,  pid, status, closing_date, supply_date, closing_time,
                supplier,     
                id || '-' || supplier as hash_key,
                (SELECT strcompanyname FROM tbl_customer 
                 WHERE lngcustomerid = supplier
                ) as supplier_name,
		accepted as bid_accepted,
		(	SELECT COUNT(rid) FROM rfq_response WHERE rfq_response.rid = rfq.id
		    	AND supplier = rfq_supplier.supplier
		) as bid_submitted,
		( 	SELECT strname FROM tbl_projecttypes, tbl_projects 
			WHERE lngindex = tbl_projects.lngprojecttype
			AND lngprojectindex = rfq.pid
		) as project_type,

		(   SELECT strprojectreference FROM tbl_projects
             WHERE lngprojectindex = rfq.pid
        ) as ref,

		now() > closing_date as closed,

		(SELECT sum(price1) FROM rfq_response rr 
		 WHERE rr.rid = rfq.id AND rr.supplier = rfq_supplier.supplier) as price1,
		(SELECT sum(price2) FROM rfq_response rr 
		 WHERE rr.rid = rfq.id AND rr.supplier = rfq_supplier.supplier) as price2,
		(SELECT sum(price3) FROM rfq_response rr 
		 WHERE rr.rid = rfq.id AND rr.supplier = rfq_supplier.supplier) as price3
        FROM    rfq, rfq_supplier
        WHERE   rfq.id = rfq_supplier.rfq
    };
    if ( defined $sup ) {
        $sql .= q{
            AND     supplier = ?
        };
        push @params, $sup;
    }

    

    push @params, $variable->{StartDate}, $variable->{EndDate};
    $clause .= ' AND closing_date BETWEEN ? AND ? ';
       

	my $rfq_status = $r->param('ddmRFQStatus') || 'Open';
    if ( grep {/$rfq_status/} qw(Awarded Open Closed) ) {

print STDERR "STATUS SLECTED: $rfq_status \n"; 

        $clause .= ' AND status = ?';
        push @params, $rfq_status;
    };

    $sql .=  $clause;
print STDERR "HAVE SEARCH SQL: \n $sql \n", Dumper(\@params);


    my $rfqs = $dbh->selectall_hashref($sql, 'hash_key',undef, @params);

	if ( $r->param('ddmRFQStatus') eq 'Received' ) {
		map {
print STDERR "CHECK BID: $rfqs->{$_}{status} Count:  $rfqs->{$_}{bid_submitted}  \n";
			delete $rfqs->{$_} 
				if $rfqs->{$_}{bid_submitted} == 0 or $rfqs->{$_}{status} eq 'Awarded';
		} keys %{$rfqs};
	}

    my @rfq;
    map { $rfqs->{$_}{services} = rfq_services($dbh, $rfqs->{$_}->{id}); 
		  $rfqs->{$_}{bid_status} =  $rfqs->{$_}{bid_accepted}         ? 'Awarded'  :  
									 $rfqs->{$_}{bid_accepted} eq '0'  ? 'Declined'  :  
									 $rfqs->{$_}{bid_submitted}        ? 'Submitted' : 'N/A';
          push @rfq , $rfqs->{$_}                        
    } sort { $a cmp $b } keys %{$rfqs};

    @rfq = grep {$_->{pid} == $pid} @rfq if $pid;

print STDERR "HAVE RFQ DATA: ", Dumper(\@rfq);

    return \@rfq;


}

sub admin_list {
    my ($r, $dbh, $var) = @_;
    my $show_all = 1 if $var->{user_type} ne 'C';
    rfq_list($r, $dbh, $var, $show_all);

	$var->{"ddmRFQStatus". $r->param('ddmRFQStatus')} = 'selected';

}


sub bid_history {
    my ($r, $dbh, $var, $show_all) = @_;
	
	my @bids;
	my $data = $dbh->selectall_hashref(q{
		SELECT (SELECT strServiceType FROM tbl_project_contents 
				WHERE lngserviceindex = bid_history.sid
			   ) as service, 
				*, 
				to_char(date,'YY-MM-DD HH::MI::SS') ||
					(SELECT strServiceType FROM tbl_project_contents 
					 WHERE lngserviceindex = bid_history.sid
			   		) as id, 
			   (SELECT strFirstname || ' ' || strLastname
				FROM tbl_customer_users 
				WHERE tbl_customer_users.lnguserid = bid_history.uid
			   ) as user_name
		FROM bid_history WHERE rid = ? AND supplier = ? ORDER by date;
	}, 'id', undef, $r->param('rid'), $r->param('supplier'));

	map { push @bids, $data->{$_} } sort { $a cmp $b } keys %{$data};

	$var->{bids} = \ @bids;
}

sub send_po {
	my ( $r, $log, $dbh, $variable ) = @_;

print STDERR "SEND MY PO *********";

	my $rid    = $r->param('rid');
	my $sup_id = $r->param('sup_id');

    my $rsf = $dbh->prepare(q{ UPDATE rfq_supplier SET accepted = false 
								    WHERE rfq = ? });
    my $rst = $dbh->prepare(q{ UPDATE rfq_supplier SET accepted = true 
								    WHERE supplier = ? and rfq = ? });
    $rsf->execute($rid);
    $rst->execute($sup_id, $rid);

    my $rsa = $dbh->prepare(q{ UPDATE rfq SET status = 'Awarded' 
								    WHERE id = ? });
    $rsa->execute($rid);


    my $date = $dbh->prepare(q{ 
		UPDATE rfq SET  supply_date = ?  WHERE id = ?  
	});
	$date->execute($r->param('DPC_supply'), $rid) if $r->param('DPC_supply') ne 'TBD';
	
	my %info;
   	my $email_template = misc::load_file($r, '/email/forms/award_order.html');

	$info{'rid'} = $rid;
	$info{'pid'} = $r->param('pid');
	$info{'sup_id'} = $sup_id;
    $info{'siteURL'}  = "http://" . $r->hostname;

   	$_ = encode_qp( ssi::variable_substitution($r, $r->log, $dbh, $email_template, \%info));

   	my @body = ('', $_, 'text/html', 'quoted-printable');

   	my $email_addr = join(',', $r->param('users'));

	my $em = $dbh->prepare(q{ UPDATE rfq set po_email = ? WHERE id = ? });
	$em->execute($email_addr, $rid);

   	my %mail = (
          SMTP    => configuration::get_value($r->log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($r->log, $dbh, 'AdministratorEmail'),
          BCC      => $email_addr,
          SUBJECT => "Bid Accepted",);

    misc::send_email_with_attachment($r, $r->log, \%mail, @body);
	
	$variable->{rid}	= $rid;
	$variable->{pid} 	= $r->param('pid');
	$variable->{sup_id} = $sup_id;

	

}

sub make_po {
	my ( $r, $dbh, $award, $rid, $sup_id ) = @_;

print STDERR "******* MAKE PO ******** \n\n";
	my $po = $dbh->prepare(q{ 
			UPDATE rfq SET po =  
				to_char(NOW(), 'yyyy') || to_char(nextval('rfq_po_seq'),'FM0000')
			WHERE ID = ? });

	my $po_date = $dbh->prepare(q{ UPDATE rfq SET po_date = NOW() WHERE ID = ? });

	$po->execute($rid);
	$po_date->execute($rid);

	
}
sub cancel_po {
	my ( $r, $dbh, $rid, $sup_id ) = @_;

	my $com = $r->param('RFQCancelPOComments');

print STDERR "******* CANCEL PO - $rid - $com ******** \n\n";
	my $po = $dbh->prepare(q{ 
			UPDATE rfq SET status = 'Cancelled', cancel_comments = ? WHERE ID = ? 
	});

	$po->execute($com, $rid);

	my %info;
   	my $email_template = misc::load_file($r, '/email/forms/cancel_po.html');
	$info{'pid'}    = $r->param('pid');
	$info{'rid'}    = $r->param('rid');
	$info{'sup_id'} = $r->param('sup_id');
	$info{'cancelcomments'} = $com;
    $info{'siteURL'}  = "http://" . $r->hostname;

   	$_ = encode_qp( ssi::variable_substitution($r, $r->log, $dbh, $email_template, \%info));

   	my $email_addr = $dbh->selectrow_array(q{
		SELECT po_email FROM rfq WHERE id = ?
	},undef, $rid); 

   	my @body = ('', $_, 'text/html', 'quoted-printable');
   	my %mail = (
         SMTP    => configuration::get_value($r->log, $dbh, 'Mail Server'),
         FROM    => configuration::get_value($r->log, $dbh, 'AdministratorEmail'),
         BCC      => $email_addr,
         SUBJECT => "PO Cancelled",);
   	misc::send_email_with_attachment($r, $r->log, \%mail, @body);

	
}


sub award_bid {
	my ( $r, $dbh, $award, $rid, $sup_id ) = @_;
    if ( $award eq 'A' ) {
		# Award Bid.
        my $sth = $dbh->prepare(q{ UPDATE rfq_supplier SET accepted = true 
								    WHERE supplier = ? and rfq = ? });
        my $dth = $dbh->prepare(q{ UPDATE rfq_supplier SET accepted = false 
								    WHERE rfq = ? });
        $dth->execute($rid);
        $sth->execute($sup_id, $rid);

	
		my %info;
    	my $email_template = misc::load_file($r, '/email/forms/accept_bid.html');
		$info{'rid'} = $rid;
    	$info{'siteURL'}  = "http://" . $r->hostname;
    	$_ = encode_qp( ssi::variable_substitution($r, $r->log, $dbh, $email_template, \%info));

    	my @body = ('', $_, 'text/html', 'quoted-printable');

		my @emails = ('wcober@directionsolutions.com');
    	my $email_addr = join(',', @emails);

    	my %mail = (
          SMTP    => configuration::get_value($r->log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($r->log, $dbh, 'AdministratorEmail'),
          BCC      => $email_addr,
          SUBJECT => "Bid Accepted",);
    	misc::send_email_with_attachment($r, $r->log, \%mail, @body);

    } else {
		# Manual Decline Bid.
        my $sth = $dbh->prepare(q{ UPDATE rfq_supplier SET accepted = false 
								    WHERE supplier = ? and rfq = ? });
        $sth->execute($sup_id, $rid);
    } 

}

sub rfq_list {
    my ($r, $dbh, $var, $show_all) = @_;


#auto_rfq($r, $r->log, $dbh, $r->param('order_id'), $var) if $r->param('order_id');
    my $sup = $show_all ? undef : $var->{user}{company}{id};


    if ( $r->param('delete') ) {
        my $del = $dbh->prepare(q{ 
            DELETE FROM rfq_supplier WHERE rfq = ? AND supplier = ?
        });
        map { $_ =~ m/(\d*)-(\d*)/; $del->execute($1,$2) } $r->param('delete');
    }

    $var->{rfqs} = list_rfqs($r, $dbh, $var, $sup, $r->param('pid'));
    $var->{pid} = $r->param('pid');

    return;
}

sub send_rfq {
    my ($r, $dbh, $variable) = @_;
map {
print STDERR "HAVE PARAM " . $_ . "=" . $r->param($_) . "\n";
} $r->param();

    my $rid = $r->param('rid');
	my %email;
	map { $email{$_} = 1 } ($r->param('users'));

	if ( $r->param('btnFunction') eq 'Copy RFQ') {
		$rid = copy_rfq( $dbh, $variable, $rid);
		my $email = scalar $dbh->selectrow_array(q{
			SELECT email FROM rfq WHERE id = ?
		}, undef, $rid);

		email_rfq($r, $dbh, $variable, $rid, $email);

	} elsif ( $r->param('StoreRFQ') ) {

print STDERR "TIME TO STORE RFQ ONLY \n";
		store_rfq($r, $dbh,$variable->{user_id}, $rid, \%email);

	} else {
		#Somebody pushed the Send RFQ Button.

		store_rfq($r, $dbh,$variable->{user_id}, $rid, \%email);

		my $api_suppliers = $dbh->selectall_hashref(q{
			SELECT lngcustomerid FROM tbl_customer WHERE api_URL IS NOT Null
		},'lngcustomerid',{});
		my $pid = $r->param('pid');
		

		foreach my $supid ( $r->param('suppliers') ) { 
			if ( $api_suppliers->{$supid} ) {
				api_bid($r, $dbh, $variable, $supid, $rid, $pid );
				my $sup_email = $dbh->selectcol_arrayref(q{
					SELECT stremail FROM tbl_customer_users WHERE lngcustomerid = ?
				}, undef, $supid);
				map { delete $email{$_} } @{$sup_email};
			}	
		}

		if ( keys %email ) {
			my $email_addr = join(',', keys %email);
			email_rfq($r, $dbh, $variable, $rid, $email_addr);
			print STDERR "email users : $email_addr ";
		}

	}
}

sub store_rfq {

	my ( $r, $dbh, $user_id, $rid, $email ) = @_;

	my $email_addr = join(',', keys %{$email});

	my $sth = $dbh->prepare(q{ INSERT INTO rfq_supplier  VALUES (?, ?) });

	map {$sth->execute($rid, $_)} $r->param('suppliers');

	my $new = $dbh->prepare(q{
		UPDATE rfq SET 
				closing_date = ?,   supply_date  = ?,  	comments = ?, 
				creator      = ?, 	closing_time = ?, 	sent_to   = ?
		WHERE id = ?
	});

	my $closing = $r->param('DPC_closing');
	my $supply  = $r->param('DPC_supply') || undef;
	   $supply  = undef if $supply eq 'TBD';

	my $comments = $r->param('RFQComments');

	my $time = $r->param('closing_time');

	$new->execute($closing, $supply, $comments, $user_id, $time, $email_addr, $rid);
	
}

sub email_rfq {

	my ( $r, $dbh, $variable, $rid, $email ) = @_;
    my $log = $r->log;

    load_rfq($r, $log, $dbh, $variable, $rid,undef,$variable->{user}{company}{id});

	map { print STDERR "SERVICE: $_->{ref} \n"; } @{$variable->{RFQ}};

    my $order_id = $variable->{order_id};
    #return unless $order_id;

    eprint::order::get_invoice_to($log, $dbh, $variable, $order_id) if $order_id;
    eprint::order::get_ship_to($log, $dbh, $variable, $order_id) if $order_id;
    eprint::order::get_misc($log, $dbh, $variable, $order_id) if $order_id;
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

 print STDERR "SENDING MAIL TO : $email \n";

	my $sth = $dbh->prepare(q{UPDATE rfq set email = ? where id = ? });
	$sth->execute($email, $rid);
	
    my %mail = (
          SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          TO      => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          BCC     => $email,
          SUBJECT => "RFQ",);
    misc::send_email_with_attachment($r, $log, \%mail, @body);





}
sub new_rfq {
    my ($dbh, $pid) = @_;
    my $sth = $dbh->prepare(q{
        INSERT INTO rfq (pid) VALUES ( ? )
    });
    $sth->execute($pid);

#    my $rid = $dbh->last_insert_id(undef, undef, 'rfq', 'id');
    my $rid = scalar $dbh->selectrow_array(q{
    	SELECT MAX(id) FROM rfq
    });
    return $rid;
}

sub copy_rfq {

	my ($dbh, $var, $old_rid) = @_;

	my $rfq = $dbh->prepare(q{
		INSERT INTO rfq ( 
			pid, 		status, 	closing_date, 	supply_date, 
			send_date, 	creator, 	comments, 		scomments, 
			email 
		)  SELECT 
			pid, 		status, 	closing_date, 	supply_date,
			now(), 		creator, 	comments, 		scomments, 
			email 
	    FROM rfq WHERE id = ?
	});
	$rfq->execute($old_rid);

    my $rid = scalar $dbh->selectrow_array(q{
    	SELECT MAX(id) FROM rfq
    });

	my $services = $dbh->prepare(q{
		INSERT INTO rfq_services 
			SELECT ?, sid, info_only, id 
			FROM rfq_services WHERE rid = ?
	});
	$services->execute($rid, $old_rid);

	my $sth = $dbh->prepare(q{ INSERT INTO rfq_supplier 
			SELECT ?, supplier, accepted, comments FROM rfq_supplier WHERE rfq = ?
	});
	$sth->execute($rid, $old_rid);

	return $rid;

}

sub create_rfq {
    my ($r, $dbh) = @_;
    my @services  = $r->param('rfq');
    my @info_only = $r->param('info_only');

	print STDERR "HAVE SERVICES", Dumper(\@services);

    my $rid = new_rfq($dbh, $r->param('pid'));


	my $st = $dbh->prepare(q{
		SELECT strservicetype FROM tbl_project_contents WHERE lngserviceindex = ?
	});
	my %service;

	map { $st->execute($_); $service{$_} = $st->fetchrow_array() } $r->param('rfq');
	
	my $map = $dbh->selectall_arrayref(q{
		SELECT s.strid
		FROM   tbl_service_types s, tbl_service_categories c 
		WHERE  s.strcategory = c.strid order by c.lngsort, s.lngsort;
	});

	my @sort;
	foreach my $x ( @{$map} ) {
		map { 
			push @sort, $_ if $x->[0] eq $service{$_}; 
		} keys %service;
	};

    my $sth = $dbh->prepare(q{
        INSERT INTO rfq_services  VALUES ( ?, ?, ? )
    });

    map {$sth->execute($rid, $_, $r->param("$_-info_only") || 0)} $r->param('rfq');

    return $rid;
    
}

sub auto_rfq {
    my ($r,$log, $dbh, $order_id) = @_;
    
    return unless $order_id;
    
    my $pid  = scalar $dbh->selectrow_array(q{
	SELECT lngprojectindex FROM tbl_order_contents 
	WHERE  lngorderid =  ?
    },undef, $order_id);

    my $sup = scalar $dbh->selectrow_array(q{
	SELECT lngcustomerid FROM tbl_customer WHERE strCompanyName = (
	    SELECT strSupplier FROM tbl_equipment WHERE lngindex = (
		SELECT strvalue::integer FROM tbl_service_specifications
		WHERE lngprojectindex = ? AND strname = 'press'
		LIMIT 1
	    )
	)
    }, undef, $pid);

print STDERR "AUTO RFQ - $order_id PID: $pid SUP: $sup  \n ";

    my $rid = new_rfq($dbh, $pid);
	$dbh->do(qq{ UPDATE rfq SET closing_date=now(), send_date=now(), supply_date=now() WHERE id = $rid});

    my $rs = $dbh->prepare(q{ INSERT INTO rfq_supplier VALUES ( ?, ?, true) });
    $rs->execute($rid, $sup);


	my $sids = $dbh->selectcol_arrayref(q{
		SELECT lngserviceindex FROM tbl_project_contents WHERE lngprojectindex = ?
	}, undef, $pid ); 

    my $services = $dbh->prepare(qq{ INSERT INTO rfq_services VALUES ( ?, ?) });

    my $bid = $dbh->prepare(qq{
		INSERT INTO rfq_response VALUES ( ?, ?, ?,
			( SELECT SUM(strvalue::Numeric(10,2)) FROM tbl_service_specifications
		  		WHERE lngserviceindex = ? and  strname IN ('txtPrice1', 'txtStockPrice1')
			)
		)
	});

	map { 
    	 	$services->execute($rid, $_);
			$bid->execute($rid, $_, $sup, $_) 
	} @{$sids}; 


    my $email_template = misc::load_file($r, '/email/email_template.html');
    my %info;
    $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/notify_supplier_project_awarded.html\"-->";
    $info{'pid'} = $pid;
    $info{'rid'} = $rid;
   	$info{'siteURL'}  = "http://" . $r->hostname;

    $_ = encode_qp( ssi::variable_substitution($r, $log, $dbh, $email_template, \%info));
    my @body = ('', $_, 'text/html', 'quoted-printable');
    my @email_addr = scalar $dbh->selectrow_array(q{
    	SELECT strEmail FROM tbl_customer_users WHERE lngcustomerid = ?
    }, undef, $sup);
    my $to = join(',',@email_addr);
 print STDERR " EMAIL TO : $to \n";
    my %mail = (
          SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          TO      => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          BCC     => $to,
          SUBJECT => "New Project",);
    misc::send_email_with_attachment($r, $log, \%mail, @body);

}

1;
