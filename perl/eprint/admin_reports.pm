package eprint::admin_reports;
use strict;

# TODO I'm sure this module can be cleaned up even further -- I've rewritten
# it from the 2600 line monstrosity it was before, but had to kind of rush,
# and fear it might still be inadequate.

use HTML::Entities qw( encode_entities                        );
use List::Util   qw( sum                                );
use sql          qw(                                    );
use ssi          qw( get_start_end_dates make_drop_down );
use DateTime;

use MIME::QuotedPrint;

use eprint::Service::Shipping;

require misc;
our @QBE_HEADER_LINE;
    $QBE_HEADER_LINE[0]  = 'HDR';
    $QBE_HEADER_LINE[1]  = 'QuickBooks For Windows';
    $QBE_HEADER_LINE[2]  = 'All Versions';
    $QBE_HEADER_LINE[3]  = 'All Releases';
    $QBE_HEADER_LINE[4]  = '1';
    $QBE_HEADER_LINE[7]  = 'N';

our @INVOICE_LINE;
    $INVOICE_LINE[0]  = 'TRNS';
    $INVOICE_LINE[2]  = 'INVOICE';
    $INVOICE_LINE[4]  = 'Accounts Receivable';
#    $INVOICE_LINE[6]  = '***************';
    $INVOICE_LINE[10] = 'N';
    $INVOICE_LINE[11] = 'N';
    $INVOICE_LINE[35] = 0;
    $INVOICE_LINE[36] = 0;

our @SPL_LINE;
    $SPL_LINE[0]      = 'SPL';
    $SPL_LINE[2]      = 'INVOICE';
#    $SPL_LINE[6]      = '*****************';
    $SPL_LINE[10]     = 'N';
    $SPL_LINE[15]     = 'N';
    $SPL_LINE[16]     = 'NOTHING';
    $SPL_LINE[18]     = '0/0/0';

our @PAYMENT_LINE;
    $PAYMENT_LINE[0]  = 'TRNS';
    $PAYMENT_LINE[2]  = 'PAYMENT';
    $PAYMENT_LINE[4]  = 'Undeposited Funds';
    $PAYMENT_LINE[10] = 'N';
    $PAYMENT_LINE[11] = 'N';
    $PAYMENT_LINE[19] = 'N';

our @PAYMENT_SPL;
    $PAYMENT_SPL[0]   = 'SPL';
    $PAYMENT_SPL[2]   = 'PAYMENT';
    $PAYMENT_SPL[4]   = 'Accounts Receivable';
    $PAYMENT_SPL[10]  = 'N';
    $PAYMENT_SPL[15]  = 'N';
    $PAYMENT_SPL[16]  = 'NOTHING';
#Quick Books Enteprise Header

use constant QBE_HEADER => qw(
    !HDR        PROD    VER     REL IIFVER  DATE    TIME    ACCNTNT 
);

use constant DEFAULT_TRNS => qw(
   !TRNS       TRNSID   TRNSTYPE   DATE        ACCNT
    NAME       CLASS    AMOUNT     DOCNUM      MEMO
    CLEAR      TOPRINT  ADDR1      ADDR2       ADDR3
    ADDR4      ADDR5    DUEDATE    TERMS       PAID
    PAYMETH    SHIPVIA  SHIPDATE   OTHER1      REP
);

use constant INVOICE_HEADER => ( DEFAULT_TRNS, qw(
    FOB        PONUM    INVTITLE   INVMEMO     SADDR1
    SADDR2     SADDR3   SADDR4     SADDR5      PAYITEM
    YEARTODATE WAGEBASE
) );

use constant DEFAULT_SPL => qw(
    !SPL        SPLID    TRNSTYPE   DATE        ACCNT
     NAME       CLASS    AMOUNT     DOCNUM      MEMO
     CLEAR      QNTY     PRICE      INVITEM     PAYMETH
     VALADJ     REIMBEXP TAXCODE    SERVICEDATE OTHER2
     OTHER3     PAYITEM  YEARTODATE WAGEBASE    EXTRA
);

use constant DEFAULT_END => qw(
    !ENDTRNS
);

sub save_account_numbers {
	my ($r, $dbh) = @_;
	my $xth = $dbh->prepare(q{
		INSERT INTO tbl_service_specifications VALUES (?,?,?,?,true); 
	});

	my $dth = $dbh->prepare(q{
		DELETE FROM  tbl_service_specifications
		WHERE lngserviceindex = ? AND strname = ? 
	});

	my $sidh = $dbh->prepare(q{
		SELECT sid FROM ship_address WHERE shipid = ?
	});
	my $pidh = $dbh->prepare(q{
		SELECT lngprojectindex  FROM tbl_project_contents  WHERE lngserviceindex = ?
	});
	map {
		if ( $_ =~ /acc-(\d*)/ ) {

			$sidh->execute($1);
			my $sid = $sidh->fetchrow_array();

			$pidh->execute($sid);
			my $pid = $pidh->fetchrow_array();

			$dth->execute($sid, "accountnumber-$1");
			$xth->execute($pid, $sid, "accountnumber-$1", $r->param($_));

			print STDERR " update PARAM: $_ - $1 - S: $sid P: $pid \n";
		}
		print STDERR " HAVE PARAM: $_ - $1 \n";
	} $r->param();

}
sub billing_report_data {
	my ($r, $dbh, $var) = @_;

	my $shipq = q{
		SELECT shipid FROM ship_address, tbl_addresses
		WHERE ship_address.shipid = tbl_addresses.lngindex
		AND sid IN ( 
			SELECT lngserviceindex FROM tbl_project_contents
			WHERE lngprojectindex = ?
		)
	};

	my $cch = $dbh->prepare(q{
		SELECT strname, strvalue FROM tbl_service_specifications 
		WHERE lngprojectindex = ? AND strname ~ ? 
	});



	my $query = qq{
		SELECT *, DATE(completion_date) as date 
		FROM tbl_orders, tbl_order_contents, tbl_projects, tbl_customer
		WHERE tbl_orders.lngorderid = tbl_order_contents.lngorderid
		AND tbl_order_contents.lngprojectindex = tbl_projects.lngprojectindex
		AND tbl_customer.lngcustomerid = tbl_projects.lngcustomerid
		AND DATE(completion_date) BETWEEN DATE(?) AND DATE(?)
		AND tbl_projects.strstatus = 'Complete'
		AND tbl_projects.division = ?

		ORDER by daterequired
--		LIMIT 401

	};

    my @bind_params = ( $var->{StartDate}, $var->{EndDate}, $r->param('division') );

	
    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);


    my $projects = $sth->fetchall_arrayref({});
	use Data::Dumper;

print STDERR "HAVE DIVISOIN: $var->{division} Projects FOUND: " . @{$projects} . "  \n";



	my @data;
	my $bd = $dbh->prepare(q{ SELECT bdate FROM bill_date WHERE shipid = ? });

	my $divs = $dbh->selectall_arrayref(q{
		SELECT * from division WHERE id <> ? ORDER by name
	},{Slice => {}}, $r->param('division'));

	my $ccf = $r->param('cost_center');
	my $dep_filter = $r->param('department');
print STDERR "HAVE COST CENTER FILTER: $ccf \n";

	map {
		my $i     = $_->{intquantityindex};
		my $pid   = $_->{lngprojectindex};
		my $oqty  = $_->{intquantity};
		my $ships = $dbh->selectcol_arrayref($shipq, {}, $pid);

		my $billonrelease = $dbh->selectrow_array(q{
			SELECT strvalue FROM tbl_service_specifications 
			WHERE lngprojectindex = ? AND strname = 'BillOnRelease'
		}, undef, $pid);

		my @prices = $billonrelease ? (0,0,0) 
									: eprint::project::project_price( $r->log, $dbh, $pid );

print STDERR "HAVE PRICES: $billonrelease ", Dumper(@prices);


		my $order_id = $dbh->selectrow_array(q{

			SELECT lngorderid FROM tbl_order_contents WHERE lngprojectindex = ?
		}, undef, $pid);

		my $customername = $dbh->selectrow_array(q{
			SELECT strcompanyname FROM tbl_customer, tbl_projects 
			WHERE  lngprojectindex = ? AND tbl_projects.lngcustomerid = tbl_customer.lngcustomerid
		}, undef, $pid);

		foreach my $ship ( @{$ships} ) {
			$bd->execute($ship);
			my ($bill_date) = $bd->fetchrow_array();

			next if ( $r->param('bill_filter') eq 'Billed'   && !$bill_date);
			next if ( $r->param('bill_filter') eq 'UnBilled' &&  $bill_date);

			$cch->execute($_->{lngprojectindex}, $ship);
			my $cc = $cch->fetchall_hashref(['strname']);
			my $id = "add_qty$i-$ship";
			my $q = $cc->{"add_qty$i-$ship"}->{strvalue};

			my $an =   $cc->{"accountnumber-$ship"}->{strvalue};
			my $dep =  $cc->{"department-$ship"}->{strvalue};

			my $c =   $cc->{"cost_center-$ship"}->{strvalue} eq 'manualcostcenter'
					? $cc->{"manualcostcenter-$ship"}->{strvalue}
					: $cc->{"cost_center-$ship"}->{strvalue};
			
			$c = 'Bill on Release' if $billonrelease;
			

			next if $ccf eq '99' && ! ($c =~ /^99/);
			next if $ccf eq 'Non99' && $c =~ /^99/;
			next if $ccf eq 'Non99' && $c =~ /^0000/;
			next if $ccf eq '0000'  && ! ($c =~ /^0000/ || $c eq '');
			next if $ccf eq 'BOR' 	&& ! $billonrelease;

			next if $dep_filter && $dep_filter ne 'Empty' && $dep_filter ne $dep;
			next if $dep_filter eq 'Empty' && $dep;

			my $qty = $cc->{"add_qty${i}-$ship"}->{strvalue};
			
			my $cost = $q && $oqty ? $prices[$i-1] / $oqty * $q : 0;

			my $period = $r->param('period');

			my $ordered_by = $dbh->selectrow_array(q{
				SELECT strfirstname || ' ' || strlastname from tbl_orders
				WHERE lngorderid = ?
			}, undef, $order_id);

			my $safeway_cost_center = $r->param('division') == 2 ?'6770-909 / Acct 391-696' : '9946-909 / Acct 391696';


			#print STDERR "STUFF", Dumper($cc, $q, $i, $id, $ships);
			push @data, { 	
						date  			=> $_->{date},
						job   			=> $_->{strdescription},
						cost  			=>      sprintf("%.2f", $cost),
						amount 			=> '$'. sprintf("%.2f", $cost),
						qty   			=> $q,
						cost_center  	=> $c,
						account_number  => $an,
						department  	=> $dep,
						pid   			=> $pid,
						qty	  			=> $qty,
						ordered_by 		=> $ordered_by,
						id    			=> $ship,
						period 			=> $period,
						bill_date 		=> $bill_date,
						customername 	=> $customername,
						order_id 		=> $order_id,
						divs 			=> $divs,
						credit_cost_center => $safeway_cost_center,
		
			}; 
		}
	} @{$projects};
my $x = scalar @data;
print STDERR "HAVE $x PROJECTS AFTER FILTER \n";

# Limit results to 400 Records to prevent form from having too much 
# data to submit.
	if ( scalar @data  > 400 ) {
		$var->{over_limit} = 1;
		return [];
	}

	return \@data;

}

sub send_billing_report {
	my ($r, $dbh, $data) = @_;

	my $bill_to = 'Safeway Corp - Pleasanton, CA 94588';
	my $safeway_cost_center = $r->param('division') == 2 ?'6770-909 / Acct 391-696' : '9946-909 / Acct 391696';
	my $sth = $dbh->prepare(q{
		INSERT INTO bill_date VALUES ( ?, NOW() )
	});
	my @cols;

	my @report;
	if ( $r->param('division')  == 2 ) {
		push @report, ['Period','Quantity', 'Description', 'Billed Cost Center', 'Amount', 
					   'Billed Account Number', 'Bill To', 'Credited Cost Center'];

		@cols = qw( period qty job cost_center amount account_number);
	} else { 
		push @report, ['Date','Period','Order Id', 'Quantity', 'Description', 'Billed Cost Center', 'Amount', 
					   'Billed Account Number', 'Bill To', 'Credited Cost Center'];

		@cols = qw( date period order_id qty job cost_center amount account_number);
	}
	my %checks;
	my $x = $r->param('export_entry');
	my $y = ref $x;

print STDERR "HAVE DATA:  -- \n", Dumper($x, $data);
	map {
		$checks{$_} = 1;
		$sth->execute($_);
	} $r->param('export_entry');


	map {
		push(
			@report, [@$_{@cols}, $bill_to, $_->{credit_cost_center}]
		) if $checks{$_->{id}};
print STDERR "EMAIL DATA: ", Dumper($_);
	} @{$data};

	$data = \@report;

	my $csv = Text::CSV_XS->new({ eol => "\n" });
	my $output;

	foreach my $line (@report) {
		$csv->combine(@{ $line });
		$output .= $csv->string();
	}



	my $email_template = misc::load_file($r, '/email/email_template.html');

	my %info;

	$info{'siteURL'} = "http://" . $r->hostname;

	$info{ReplacementText}
		= q{<!--#include virtual="/email/content/internal_billing_invoice.html"}
		. q{-->};

	$email_template
		= ssi::variable_substitution($r, $r->log, $dbh, $email_template, \%info);

	 my $email = configuration::get_value( $r->log, $dbh, 'AccountingEmail');

	 $email .= ',' .$r->param('email');

	 my %mail = (
		 SMTP    => configuration::get_value( $r->log, $dbh, 'Mail Server'),
		 FROM    => configuration::get_value( $r->log, $dbh, 'AccountingEmail'),
		 TO      => $email,

		 SUBJECT => "Invoice From SAFEWAY COST CENTER $safeway_cost_center",
	 );

	 misc::send_email_with_attachment(
		 $r, $r->log, \%mail, '', encode_qp($email_template), 'text/html',
		 'quoted-printable', 'data.csv',$output, 'text/csv','quoted-printable'
	 );
	return $output;
}

sub update_division {
	my ($r, $dbh ) = @_;
	map {
		if ( $_ =~ /division_(\d*)/ ) {
			$dbh->do(q{
				UPDATE tbl_projects SET division = ? where lngprojectindex = ?
			}, undef, $r->param($_), $1);
			print STDERR "UPDATE: $1 = " . $r->param($_) . " \n";
		}
	} $r->param();

}

sub internal_billing {
    my ($r, $log, $dbh, $var) = @_;

    initialise_drop_downs( $r, $log, $dbh, $var );

	my $sql = q{ SELECT id, name FROM division order by name };
	$var->{division} = ssi::fill_drop_down( $r->log, $dbh, $sql, $r->param('division') );

	$var->{__FillInForm}{bill_filter} = $r->param('bill_filter') || 'UnBilled';
	$var->{__FillInForm}{cost_center} = $r->param('cost_center');
	$var->{__FillInForm}{department}  = $r->param('department');

	$var->{projects} = [];

	return unless $r->param('division');

	update_division($r, $dbh);

	save_account_numbers($r, $dbh) if  $r->param('Save');

	my $data = billing_report_data($r, $dbh, $var);

	if ($r->param('btnFunction') eq 'Send Selected Invoices') {
		$var->{email_data} = send_billing_report($r, $dbh, $data);
		$var->{email_data} =~ s/\n/\<br\/\>/g;
	} else {
		$var->{projects} = $data;
	}

}

sub cost_center {
    my ($r, $log, $dbh, $variable) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );
	my $shipq = q{
		SELECT shipid FROM ship_address
		WHERE sid IN ( 
			SELECT lngserviceindex FROM tbl_project_contents
			WHERE lngprojectindex = ?
		)
	};

	my $cch = $dbh->prepare(q{
		SELECT strname, strvalue FROM tbl_service_specifications 
		WHERE lngprojectindex = ? AND strname ~ ? 
	});

	my $query = q{
		SELECT *, DATE(daterequired) as date 
		FROM tbl_orders, tbl_order_contents, tbl_projects 
		WHERE tbl_orders.lngorderid = tbl_order_contents.lngorderid
		AND tbl_order_contents.lngprojectindex = tbl_projects.lngprojectindex
		AND DATE(daterequired) BETWEEN DATE(?) AND DATE(?)
		AND tbl_projects.strstatus = 'Complete'
		ORDER by daterequired

	};

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate} );

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    my $projects = $sth->fetchall_arrayref({});
	use Data::Dumper;

	my @data;
	map {
		my $i     = $_->{intquantityindex};
		my $pid   = $_->{lngprojectindex};
		my $oqty  = $_->{intquantity};
		my $ships = $dbh->selectcol_arrayref($shipq, {}, $pid);
		my @prices = eprint::project::project_price( $log, $dbh, $pid );

		foreach my $ship ( @{$ships} ) {
			$cch->execute($_->{lngprojectindex}, $ship);
			my $cc = $cch->fetchall_hashref(['strname']);
			my $id = "add_qty$i-$ship";
			my $q = $cc->{"add_qty$i-$ship"}->{strvalue};

			my $an =   $cc->{"accountnumber-$ship"}->{strvalue};

			my $c =   $cc->{"cost_center-$ship"}->{strvalue} eq 'manualcostcenter'
					? $cc->{"manualcostcenter-$ship"}->{strvalue}
					: $cc->{"cost_center-$ship"}->{strvalue};
			
			my $cost = $q && $oqty ? $prices[$i-1] / $oqty * $q : 0;
			print STDERR "STUFF", Dumper($cc, $q, $i, $id, $ships);
			push @data, { 	
						date  => $_->{date},
						job   => $_->{strdescription},
						cost  => $cost,
						qty   => $q,
						cost_center  => $c,
						account_number  => $an,
						pid   => $pid
			}; 
		}
	} @{$projects};
	

	$variable->{projects} = \@data;

print STDERR "ORDER REPORT: " , Dumper(\@data);


    if ( $r->param('btnFunction') eq 'Download in CSV Format' ) {
        my @report;

        map {
            push(
                @report, @$_{qw( date job cost_center cost)}
            );
        } @data;

		my $header = ['date', 'job','cost_center', 'amount'];
        misc::export_csv(
            $r, $log, $variable, 'cost_center_billing.csv', $header, \@report
        );
    }


}


sub project_report {
    my ($r, $log, $dbh, $variable) = @_;


    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $header = [
        'Docket #', 'Project Reference', 'Company Name', 'Required Date',
        'Status'
    ];

    my $query = q{
        SELECT
            tbl_projects.lngcustomerid             AS customer,
            tbl_projects.lngprojectindex           AS pid,
            substr(strprojectreference, 0, 50)     AS reference,
            strcompanyname                         AS company,
            TO_CHAR(dtmcreationdate, 'mm/dd/yyyy') AS creationdate,
	    strstatus				   AS status
		
        FROM
            tbl_projects
        JOIN tbl_customer ON
            tbl_projects.lngCustomerID = tbl_Customer.lngCustomerID
        WHERE
            DATE(dtmCreationDate) BETWEEN DATE(?) AND DATE(?)
    };

#	$query .= q{ AND strstatus <> 'uncalculated'} unless $r->param('ddmStatus') eq 'uncalculated';

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate} );

	if ( $r->param('search') ) {
		$query .= q{ AND lower(strProjectReference) ~ ? };
		push @bind_params, lc($r->param('search'));
		$variable->{search} = $r->param('search');
	}
	

    my %include_map = (
        lngUserIndex                 => 'ddmEstimator',
        strStatus                    => 'ddmStatus',
        'tbl_Projects.lngCustomerID' => 'ddmCustomers',
    );

    foreach my $include_col ( keys %include_map ) {
        my $value = $r->param( $include_map{ $include_col } );
        if ($value) {
           $query .= "AND $include_col = ? ";

            push(@bind_params, $value);
        }
    }

    if ($r->param('ddmEmployees')) {
        $query .= q{
            AND tbl_Projects.lngCustomerID IN (
                SELECT
                    lngCustomerID
                FROM
                    tbl_Customer
                WHERE
                    lngSalesPerson = ?
            )
        };

        push(@bind_params, $r->param('ddmEmployees'));
    }

    $query .= "ORDER BY tbl_projects.lngProjectIndex";

print STDERR "PROJECT REPROT SQL: \n $query \n";

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    if ( $r->param('btnFunction') eq 'Download in CSV Format' ) {
        my @data;

        while (my $row = $sth->fetchrow_hashref) {
            push(
                @data, @$row{qw( pid reference company creationdate status )}
            );
        }

        misc::export_csv(
            $r, $log, $variable, 'project_report.csv', $header, \@data
        );
    }
    else {
        my $projects = $sth->fetchall_arrayref({});

        $variable->{projects} = $projects;
    }
}

sub quotes_report {
    my ( $r, $log, $dbh, $variable ) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $header = ['lngQuoteID', 'dtmQuoteDate', 'strPrepared By',
                  'strPrepared For', 'Total1', 'Total2', 'Total3' ];

    my $query = q{
        SELECT DISTINCT
            q.lngQuoteID                                  AS qid,
            TO_CHAR(q.dtmQuoteDate, 'MM/DD/YYYY')         AS qdate,
            by.strFirstName  || ' ' || by.strLastName     AS byname,
            fort.strFirstName || ' ' || fort.strLastName  AS forname,
            curTotalSale1                                 AS sale1,
            curTotalSale2                                 AS sale2,
            curTotalSale3                                 AS sale3
        FROM
            tbl_Quotes         AS q,  tbl_Quote_Users_For AS fort,
            tbl_Quote_Users_By AS by, tbl_Customer        AS c,
			tbl_quote_details  AS qd,
			tbl_projects	   AS p
        WHERE
            by.lngQuoteID  = q.lngQuoteID
        AND
            fort.lngQuoteID = q.lngQuoteID
		AND
			q.lngquoteid = qd.lngquoteid
		AND 
			qd.lngprojectindex = p.lngprojectindex
        AND
            q.dtmQuoteDate BETWEEN DATE(?) AND DATE(?)
    };

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate} );

	if ( $r->param('search') ) {
		$query .= q{ AND lower(strProjectReference) ~ ? };
		push @bind_params, lc($r->param('search'));
		$variable->{search} = $r->param('search');
	}

	

    my %sql_map = (
        'q.strStatus'     => 'ddmStatus',
        'q.lngCustomerID' => 'ddmCustomers',
    );

    foreach my $column ( keys %sql_map ) {
        my $value  = $r->param($sql_map{ $column });

        if ($value) {
           $query .= " AND $column = ? ";
            push(@bind_params, $value);
        }
    }

    if ($r->param('ddmEmployees')) {
        $query .= q{
            AND q.lngCustomerID  = c.lngCustomerID
            AND c.lngSalesPerson = ?
        };

        push(@bind_params, $r->param('ddmEmployees'));
    }

    if ( $r->param('dblTotal1') and $r->param('dblTotal2') ) {
        my @ands;
        foreach my $inc ( 1 .. 3 ) {
            push(@ands, "q.curTotalSale$inc BETWEEN ? AND ?");

            push(
                @bind_params,
                $r->param('dblTotal1'), $r->param('dblTotal2')
            );
        }

        if (scalar @ands) {
            $query .= ' AND (' . join(' OR ', @ands) . ') ';
        }
    }

    $query .= " ORDER BY qid";

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    if ( uc $r->param('btnFunction') eq 'DOWNLOAD IN CSV FORMAT' ) {
        my @data;

        while (my @row = $sth->fetchrow_array) {
            push( @data, @row );
        }

        misc::export_csv(
            $r, $log, $variable, 'quotes_report.csv', $header, \@data
        );
    }
    else {
        my $quotes = $sth->fetchall_arrayref({});
		map {
			$_->{projects} = $dbh->selectall_arrayref(q{
					SELECT q.lngprojectindex as pid, strprojectreference as reference 
					FROM tbl_quote_details q, tbl_projects p WHERE lngquoteid = ?
					AND q.lngprojectindex = p.lngprojectindex
            }, {Slice=>{}}, $_->{qid});
		} @{$quotes};
use Data::Dumper;
print STDERR "ADMIN QUOTES" , Dumper($quotes);

        foreach my $total ( 1.. 3 ) {
            $variable->{"ReportTotal$total"}
                = sum map { $_->{"sale$total"} } @{ $quotes };
        }

        $variable->{quotes} = $quotes;
    }
}

sub template_data {
    my ( $r, $log, $dbh, $variable ) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $header = [ 'OrderID', 'Order Date', 'Company Name', 'Status',
                   'Total'                                            ];

print STDERR "RUN TEMPLATE REPORT \n";

    my $query = q{
        SELECT
			lngprojectindex
        FROM
            tbl_Orders, tbl_Order_Contents
        WHERE
            dtmOrderDate::Date BETWEEN ? AND ?
        AND
            tbl_Order_Contents.lngOrderID = tbl_Orders.lngOrderID
		ORDER BY 
			tbl_Orders.lngOrderID

    };

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate} );

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    my $projects = $sth->fetchall_arrayref();

print STDERR Dumper($projects);
	my $data;

	map {
		my $pid = shift @{$_};
print STDERR "GET DATA FOR PID: $pid \n";
		use eprint::Template;
		my $datasource = eprint::Template::get_datasource($dbh, $pid);

		my $csv = Text::CSV_XS->new({
				binary   => 1, # Allow UTF-8 (and embedded newlines)
				sep_char =>',',
		}); 

		my $sth = $datasource->prepare(q{SELECT * FROM export});
		$sth->execute;

		# Send the field names as a header then the body data.
		#$data= [ 
		#	do { $csv->combine(@{ $sth->{NAME} }); $csv->string }, $/ 
		#];

		while (my $rec = $sth->fetch) { 
			push @{$data}, $rec;
		}
	} @{$projects};

print STDERR "FILE DATA: " , Dumper($data);





    if ( $r->param('Download') ) {
        misc::export_csv(
            $r, $variable, 'template_data.csv', $data, 
        );
    }
}

sub paypal {

    my ( $r, $log, $dbh, $variable ) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $header = [ 'OrderID', 'Order Date', 'Company Name', 'Status',
                   'Total'                                            ];
    my $query = q{
        SELECT
            tbl_Orders.lngOrderID                                AS id,
            to_char(tbl_payments.dtmDate, 'MM/DD/YYYY')       AS date,
            tbl_Orders.strCompanyName                            AS cname,
            tbl_payments.curAmount                              AS amount,
            tbl_Orders.curTotalSale                              AS cursale,
			tbl_payments.strdescription							AS desc,
			tbl_payments.lngindex								AS payid,
			tbl_payments.strtransactionid						AS transactionid
        FROM
            tbl_Orders,  tbl_Customer,  tbl_payments
        WHERE
            tbl_payments.dtmDate::Date BETWEEN ? AND ?
        AND
            tbl_Customer.lngCustomerID = tbl_Orders.lngCustomerID

		AND tbl_orders.lngorderid = tbl_payments.lngorderid
		AND strmethod = ?
    };

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate}, 'PayPal' );



    $query .= q{
		ORDER BY tbl_Orders.lngOrderID
	};
print STDERR "HAVE SQL QUERY FOR PAYPAL: $query \n";

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    if ( $r->param('btnFunction') eq 'Download in CSV Format' ) {
    }
    else {
        my $results = $sth->fetchall_arrayref( {} );

        $variable->{orders} = $results;
    }
}


sub order_report {

    my ( $r, $log, $dbh, $variable ) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $header = [ 'OrderID', 'Order Date', 'Company Name', 'Status',
                   'Total'                                            ];

    my $query = q{
        SELECT
            tbl_Orders.lngOrderID                                AS id,
            to_char(tbl_Orders.dtmOrderDate, 'MM/DD/YYYY')       AS date,
            tbl_Orders.strCompanyName                            AS cname,
            tbl_Orders.strStatus                                 AS status,
            tbl_Orders.curTotalSale                              AS cursale,
            tbl_Orders.strPOnumber                               AS po,
            tbl_Orders.curTotalSale - COALESCE((
                SELECT
                    SUM(curAmount)
                 FROM
                    tbl_Payments
                 WHERE
                    tbl_Payments.lngOrderiD
                        = tbl_Orders.lngOrderID
            ), 0)                                                AS balance
        FROM
            tbl_Orders, tbl_Order_Contents, tbl_Customer, tbl_projects
        WHERE
            dtmOrderDate::Date BETWEEN ? AND ?
        AND
            tbl_Order_Contents.lngOrderID = tbl_Orders.lngOrderID
        AND
            tbl_Customer.lngCustomerID = tbl_Orders.lngCustomerID
    };

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate} );

	if ( $r->param('search') ) {
		$query .= q{ AND lower(strProjectReference) ~ ? };
		push @bind_params, lc($r->param('search'));
		$variable->{search} = $r->param('search');
	}

	if ( $r->param('ddmDivision') ) {
print STDERR "HAVE DIVISION " . $r->param('ddmDivision') . " \n";
		$query .= q{ AND tbl_projects.division = ? };
		push @bind_params, $r->param('ddmDivision');
	}


    my %sql_map = (
        'tbl_Orders.strStatus'        => 'ddmStatus',
        'tbl_Orders.lngCustomerID'    => 'ddmCustomers',
        'tbl_Customer.lngSalesPerson' => 'ddmEmployees',
    );

    foreach my $col ( keys %sql_map ) {
        my $param = $r->param($sql_map{ $col });
        if ($param) {
            $query .= "    AND $col = ? ";
            push(@bind_params, $param);
        }
    }

    if ($r->param('dblTotal1') && $r->param('dblTotal2')) {
        $query .= ' AND tbl_Orders.curTotalSale BETWEEN ? AND ?';
        push(@bind_params, $r->param('dblTotal1'), $r->param('dblTotal2'));
    }

    $query .= q{
       	GROUP BY
           	tbl_orders.lngorderid, date, cname, status, cursale 
		ORDER BY tbl_Orders.lngOrderID
	};
print STDERR "HAVE SQL QUERY: $query \n";

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    if ( $r->param('btnFunction') eq 'Download in CSV Format' ) {
        my @data;

        while (my $row = $sth->fetchrow_hashref) {
            push(@data, @$row{qw( id date cname status cursale )});
        }

        misc::export_csv(
            $r, $log, $variable, 'order_report.csv', $header, \@data
        );
    }
    else {
        my $results = $sth->fetchall_arrayref( {} );

		map {
			$_->{projects} = $dbh->selectall_arrayref(q{
					SELECT o.spec_pid as pid, strprojectreference as reference 
					FROM tbl_Order_contents o, tbl_projects p WHERE lngorderid = ?
                    AND  o.spec_pid = p.lngprojectindex
            }, {Slice=>{}}, $_->{id});
		} @{$results};

        $variable->{ReportTotal}   = sum map { $_->{cursale} } @{ $results };
        $variable->{ReportBalance} = sum map { $_->{balance} } @{ $results };

        $variable->{orders} = $results;
    }
}

sub stored_report_display {
    my ( $r, $log, $dbh, $variable ) = @_;

    my $id     = $r->param('ddmStoredReport');
    my $button = $r->param('btnFunction');

    if ($button eq '<<') {
        $id = misc::nav_get_previous(
            $r, $log, $dbh, $id, 'lngReportID', 'tbl_Reports', '',
            'strReportName'
        );
    }
    elsif ($button eq '>>') {
        $id = misc::nav_get_next(
            $r, $log, $dbh, $id, 'lngReportID', 'tbl_Reports', '',
            'strReportName'
        );
    }
    elsif ($button eq 'Save') {
        my @sql = (
            strReportName => $r->param('strReportName'),
            strSQLCommand => $r->param('strSQLCommand'),
        );

        if ($id) {
            sql::update($log, $dbh, 'tbl_Reports', "lngReportId = $id", @sql);
        }
        else {
            sql::insert($log, $dbh, 'tbl_Reports', @sql);
			($id) = sql::sql_statement( $log, $dbh, 'Select max(lngReportId) From tbl_reports' );
        }
    }
    elsif ($button eq 'Delete') {
        $dbh->do(
            'DELETE FROM tbl_Reports WHERE lngReportID = ?',{}, $id
        );

        $id = misc::nav_get_previous(
            $r, $log, $dbh, $id, 'lngReportID', 'tbl_Reports', '',
            'strReportName'
        );
    }


    if ( $id ) {
        @$variable{qw( strReportName strSQLCommand )}
            = $dbh->selectrow_array(q{
                SELECT
                    strReportName, strSQLCommand
                FROM
                    tbl_Reports
                WHERE
                    lngReportID = ?
                }, undef, $id
        );
    }

    my $reports = $dbh->selectcol_arrayref(q{
        SELECT
            lngReportID, strReportName
        FROM
            tbl_Reports
		Order By strReportName
        }, { Columns => [ 1, 2 ] }
    );

    $variable->{ddmStoredReport} = make_drop_down( $reports, $id );
    $variable->{hiddenReportID}  = $id;

    return;
}

sub stored_report_process {
    my ( $r, $log, $dbh, $variable ) = @_;

    my $report = $r->param('hiddenReportID') || 0;

    # Get the SQL to run from the database and run it directly. We're going
    # to *assume* administrators aren't going to be doing SQL injection
    # attacks.
    my ($name, $sql) = $dbh->selectrow_array(q{
        SELECT
            strReportName, strSQLCommand
        FROM
            tbl_Reports
        WHERE
            lngReportID = ?
        }, undef, $report
    );

    my $sth    = $dbh->prepare($sql);
    my $result = eval { $sth->execute; };

    if ($@ || !defined $result) {
        my $error = $@ || $dbh->errstr();

        $error =~ s/</&lt;/g;

        return misc::error(
            $log, $dbh, $variable, "SQL Statement failed.",
            "It appears your SQL statement failed.  Reason:<br />"
          . "<pre>$error</pre>"
        );
    }

    if ( $r->param('btnFunction') eq 'Show Results' ) {
use Data::Dumper;
print STDERR "HAVE HEADERS: ", Dumper($sth->{NAME});

        return misc::error(
            $log, $dbh, $variable, "SQL Statement completed without Results",
            "$sql <br />"
        ) unless @{$sth->{NAME}};
		

        # We're going to do something really yuck and build an HTML table
        # with strings right here. Why re-invent a crappy wheel when great
        # ones exist you ask? Deadline of 5min including deployment I say.
        $variable->{RESULTS} = "<table class='common'>\n<thead>\n\t<tr>\n";

        foreach my $headers (@{ $sth->{NAME} }) {
            $variable->{RESULTS} .= "\t\t<th>"
                                 .  encode_entities($headers)
                                 .  "</th>\n";
        }

        $variable->{RESULTS} .= "\t</tr>\n</thead>\n<tbody>\n";

        my $offset = 0;

        while (my $row = $sth->fetchrow_arrayref) {
            $offset ^= 1;
            map { s{\n}{<br />}gs; $_ } @{ $row };
            $variable->{RESULTS} .= "\t<tr class='r$offset'>\n"
                                 .  "\t\t<td>"
                                 .  join("</td>\n\t\t<td>", @{ $row })
                                 .  "</td>\n"
                                 .  "\t</tr>\n";
        }

        $variable->{RESULTS} .= "</tbody>\n</table>\n";
    }
    elsif ( $r->param('btnFunction') eq 'Download in CSV Format' ) {
        my @data;

        push(@data, @{ $_ }) while $_ = $sth->fetch;

        misc::export_csv(
            $r, $log, $variable, $name . '.csv', $sth->{NAME}, \@data
        );
    }
}

sub accounting_report {
    my ($r, $log, $dbh, $variable) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $csv     = defined $r->param('Export');
    my @entries = $r->param('export_entry');
    my $invoice =    $r->param('ddmExport') eq 'Invoices' 
                  || $r->param('ddmExport') eq 'InvoicesSimple'
                  || $r->param('ddmExport') eq 'Estimates';

    return !$csv     ? display_accounting_reports($r, $log, $dbh, $variable)
         :  $invoice ? send_orders_csv($r, $dbh, $variable, \@entries)
         :             send_payments_csv($r, $dbh, $variable, \@entries);
}

sub send_orders_csv {
    my ($r, $dbh, $variable, $entries) = @_;

    my @returntimes = @{ $dbh->selectcol_arrayref(q{
        SELECT
            lngorderid
        FROM
            tbl_orders
        WHERE
            dtmmodifieddate > dtmexportdate
        ORDER BY
            lngorderid
    }) };

    my @nulltimes = @{ $dbh->selectcol_arrayref(q{
        SELECT
            lngorderid
        FROM
            tbl_orders
        WHERE
            dtmexportdate IS NULL
        ORDER BY
            lngorderid
    }) };

    my $orders = get_orders_sth(
        $r, $dbh, $variable->{StartDate}, $variable->{EndDate}
    );

    my @lines;
    push @lines, ([QBE_HEADER], \@QBE_HEADER_LINE) if $r->param('ddmFormat') eq 'QuickBooksEnterprise';
    push @lines,(invoice_array(INVOICE_HEADER),
                 invoice_array(DEFAULT_SPL ),
                 invoice_array(DEFAULT_END )) if $r->param('ddmFormat') ne 'SimplyAccounting';

    my $seq   = 0;

    ORDER:
    while (my $order = $orders->fetchrow_hashref) {
        my $order_id       = $order->{lngorderid};
        my $export_options = $r->param('ddmExportOptions');

        next ORDER if $export_options =~ /Sel/
                   && !grep { $order_id == $_ } @{ $entries };

        next ORDER if $export_options =~ /Never/
                   && !grep { $order_id == $_ } @nulltimes;

        next ORDER if $export_options =~ /Later/
                   && !grep { $order_id == $_ } @returntimes;

        $seq++;

        $dbh->do(q{
            UPDATE
                tbl_orders
            SET
                dtmexportdate = NOW()
            WHERE
                lngorderid = ?
            }, undef, $order_id
        );

        my $query = q{
            SELECT
                lngprojectindex, intquantity, dbltax1, dbltax2,
                dbltax3, cursalesprice, intquantityindex
            FROM
                tbl_order_contents
            WHERE
                lngorderid = ?
        };

        my $contents = $dbh->selectall_arrayref(
            $query, { Slice => {} }, $order_id
        );

        if ( $r->param('ddmFormat') eq 'SimplyAccounting' ) {
            push @lines, convert_to_simply($dbh, $order_id);
        } elsif( $r->param('ddmFormat') eq 'QuickBooksEnterprise')  {
            #push @lines, qb_enterprise_format($dbh, $order_id);
            push(@lines, $_) for invoice_lines($r, $dbh, $order, $contents, $seq);
        } else  {
            push(@lines, $_) for invoice_lines($r, $dbh, $order, $contents, $seq);
        }

    }
use Data::Dumper;
print STDERR "LINES : " , Dumper(@lines);
    if ( $r->param('ddmFormat') eq 'SimplyAccounting' ) {
        misc::export_csv($r, $variable, 'export_invoices.imp', \@lines);
    } else {
        misc::export_csv($r, $variable, 'export_invoices.iif', \@lines);
    }

    return;
}

sub qb_enterprise_format{
print STDERR "QB ENTERPRISE FORMAT \n\n";

    my ($dbh, $order_id) = @_;
    my @lines;

    my @cust = $dbh->selectrow_array(q{
        SELECT 
                'TRNS', 
                'TRNSID', 'INVOICE', 
                TO_CHAR(dtmOrderDate,'mm-dd-yyy'),
                'ACCNT',
                strcompanyname,      
                'CLASS',
                curTotalSale,
                lngorderid,
                '',
                'N',
                'N',
                strcompanyname,
                strAddress1,         straddress2,    strcity, 
               strstate || ' ' || strpostalcode,  
                TO_CHAR(dtmrequireddate,'mm-dd-yyyy'),
               'TERMS'
        FROM 
               tbl_orders 
        WHERE  
               lngorderid = ?
    }, undef, $order_id);
        
    my @inv = $dbh->selectrow_array(q{
        SELECT 
               0,                   '',     lngorderid,
               TO_CHAR((dtmorderdate), 'mm-dd-yyyy'), 0,
               '',                   curtotalsale,
               ( SELECT sum(dblshipping)  FROM tbl_order_contents WHERE lngorderid = ? )
        FROM
               tbl_orders 
        WHERE  
               lngorderid = ?
    }, undef, $order_id, $order_id);

    #Do a little formating on the Optional Freight Amount.
    $inv[7] = $inv[7] ? sprintf("%.2f",$inv[7]) : '0.00';

    my @projects = @{ $dbh->selectcol_arrayref(q{
        SELECT lngProjectIndex 
        FROM tbl_order_contents 
        WHERE lngorderid = ?
    }, undef, $order_id) };


    foreach my $id (@projects) {
        # Increase Detail Line Count.
        $lines[5][0]++;
        push @lines, $dbh->selectrow_arrayref(q{
            SELECT 
               'SPL'
               'TRNSID'
                'INVOICE'
                TO_CHAR(dtmOrderDate,'mm-dd-yyy'),
                'ACCNT',
               'Print Sales', 
                '',
                'AMT'
                'DOCNUM'
               curtotalsale,
               lngorderid,
               ( S - curfedtax - curprovtax) /   
               (SELECT intquantity FROM tbl_order_contents where lngprojectindex = ?))::numeric(10,2),
               (curtotalsale - curfedtax - curprovtax),   
               'GST',0,1,5,curfedtax,
               'PST',0,0,7,curprovtax
            FROM
               tbl_orders  
            WHERE  
               lngorderid = ?
        }, undef, $id, $id, $order_id);

    }
    unshift @lines, \@cust;


    return @lines;

}

sub convert_to_simply{

    my ($dbh, $order_id) = @_;
    my @lines;

    my @cust = $dbh->selectrow_array(q{
        SELECT 
               strcompanyname,      0,              strfirstname || ' ' || strlastname, 
               strAddress1,         straddress2,    strcity, 
               strstate,            strpostalcode,  strcountry, 
               strphone,            strfax,         stremail
        FROM 
               tbl_orders 
        WHERE  
               lngorderid = ?
    }, undef, $order_id);
        
    my @inv = $dbh->selectrow_array(q{
        SELECT 
               0,                   '',     lngorderid,
               TO_CHAR((dtmorderdate), 'mm-dd-yyyy'), 0,
               '',                   curtotalsale,
               ( SELECT sum(dblshipping)  FROM tbl_order_contents WHERE lngorderid = ? )
        FROM
               tbl_orders 
        WHERE  
               lngorderid = ?
    }, undef, $order_id, $order_id);

    #Do a little formating on the Optional Freight Amount.
    $inv[7] = $inv[7] ? sprintf("%.2f",$inv[7]) : '0.00';

    my @projects = @{ $dbh->selectcol_arrayref(q{
        SELECT lngProjectIndex 
        FROM tbl_order_contents 
        WHERE lngorderid = ?
    }, undef, $order_id) };

    my @header = (['<Version>'],["12001","1"],['</Version>']);

    push @lines, @header, ['<SalInvoice>'], \@cust, \@inv;

    foreach my $id (@projects) {
        # Increase Detail Line Count.
        $lines[5][0]++;
        push @lines, $dbh->selectrow_arrayref(q{
            SELECT 
               'Print Sales', 
               (SELECT intquantity FROM tbl_order_contents where lngprojectindex = ?),
               ((curtotalsale - curfedtax - curprovtax) /   
               (SELECT intquantity FROM tbl_order_contents where lngprojectindex = ?))::numeric(10,2),
               (curtotalsale - curfedtax - curprovtax),   
               'GST',0,1,5,curfedtax,
               'PST',0,0,7,curprovtax
            FROM
               tbl_orders  
            WHERE  
               lngorderid = ?
        }, undef, $id, $id, $order_id);

    }

    push @lines, ['</SalInvoice>'];

    return @lines;

}

sub send_payments_csv {
    my ($r, $dbh, $variable, $entries) = @_;

    my @returntimes = @{ $dbh->selectcol_arrayref(q{
        SELECT
            lngindex
        FROM
            tbl_payments
        WHERE
            dtmdate > dtmoutputdate
        ORDER BY
            lngindex
    }) };

    my @nulltimes = @{ $dbh->selectcol_arrayref(q{
        SELECT
            lngindex
        FROM
            tbl_payments
        WHERE
            dtmoutputdate IS NULL
        ORDER BY
            lngindex
    }) };

    my $payments = get_payments_sth(
        $r, $dbh, $variable->{StartDate}, $variable->{EndDate}
    );

    my @lines = (
        payment_array(DEFAULT_TRNS),
        payment_array(DEFAULT_SPL),
        payment_array(DEFAULT_END),
    );

    my $seq = 0;

    PAYMENT:
    while (my $payment = $payments->fetchrow_hashref) {
        my $payment_id     = $payment->{lngindex};
        my $export_options = $r->param('ddmExportOptions');

        next PAYMENT if $export_options =~ /Sel/
                     && !grep { $payment_id == $_ } @{ $entries };

        next PAYMENT if $export_options =~ /Never/
                     && !grep { $payment_id == $_ } @nulltimes;

        next PAYMENT if $export_options =~ /Later/
                     && !grep { $payment_id == $_ } @returntimes;

        $seq++;

        $dbh->do(q{
            UPDATE
                tbl_payments
            SET
                dtmoutputdate = NOW()
            WHERE
                lngindex = ?
            }, undef, $payment_id
        );

        push(@lines, $_) for payment_lines($dbh, $payment, $seq);
    }

    misc::export_csv($r, $variable, 'export_payments.iif', \@lines);

    return;
}
sub simple_lines {
    my ($r, $log, $dbh, $contents, $order, $tax, $line ) = @_;
    my @results;

    foreach my $row (@{ $contents }) {
        my @content_line = @SPL_LINE;

        my $sth = $dbh->prepare_cached(q{
            SELECT
                strprojectreference
            FROM
                tbl_projects
            WHERE
                lngprojectindex = ?
        });

        my ($proj_name)  = $dbh->selectrow_array(
            $sth, undef, $row->{lngprojectindex}
        );
        my $price = $dbh->selectrow_array(q{
            SELECT cursalesprice FROM tbl_order_contents WHERE lngprojectindex = ?
        }, undef, $row->{lngprojectindex});

        $content_line[1]  = $order->{lngorderid} . '-' . $$line++;
        $content_line[2]  = 'ESTIMATE' if $r->param('ddmExport') eq 'Estimates';
        $content_line[3]  = $order->{due_date};
        $content_line[4]  = configuration::get_value($log, $dbh, 'ServiceExportAccount');
        $content_line[7] = sprintf("%.2f", $price * -1);

        $content_line[11] = $row->{intquantity} * -1;
        $content_line[12] = sprintf("%.2f", $price);
        $content_line[13] = configuration::get_value($log, $dbh, 'ServiceExportAccount') . ":Print Project";

        $content_line[9]
            = "Project Docket $row->{lngprojectindex} - $proj_name";

        push(@results, invoice_array(@content_line));

    }

    return @results;
}

sub detail_lines {
    my ($r, $log, $dbh, $contents, $order, $tax, $line ) = @_;
    my @results;

    foreach my $row (@{ $contents }) {
        my @content_line = @SPL_LINE;

        my $sth = $dbh->prepare_cached(q{
            SELECT
                strprojectreference
            FROM
                tbl_projects
            WHERE
                lngprojectindex = ?
        });

        my ($proj_name)  = $dbh->selectrow_array(
            $sth, undef, $row->{lngprojectindex}
        );

        $content_line[1]  = $order->{lngorderid} . '-' . $$line++;
        $content_line[2]  = 'ESTIMATE' if $r->param('ddmExport') eq 'Estimates';
        $content_line[3]  = $order->{due_date};
        $content_line[4]  = configuration::get_value($log, $dbh, 'ServiceExportAccount');
#        $content_line[6]  = configuration::get_value($log, $dbh, 'ServiceExportAccount');
        $content_line[7]  = 0;
        $content_line[11] = $row->{intquantity} * -1;
        $content_line[12] = 0;
        $content_line[13] = configuration::get_value($log, $dbh, 'ServiceExportAccount') . ":Print Project";

        $content_line[9]
            = "Project Docket $row->{lngprojectindex} - $proj_name";

        push(@results, invoice_array(@content_line));

        # oh so very kludgy.
        my $query = q{
            SELECT
				ss.lngserviceindex AS index,
                st.strcategory AS category,
                st.strname     AS name,
                ss.strvalue    AS price,
                'Stock'        AS stock,
				pc.ysnremoved  AS removed,
				( SELECT strValue FROM tbl_service_specifications
				   WHERE lngserviceindex = pc.lngserviceindex
				   AND strName = 'ServiceName' 
				) 			   AS desc
            FROM
                tbl_service_types          AS st,
                tbl_project_contents       AS pc,
                tbl_service_specifications AS ss
            WHERE
                (pc.strservicetype  = st.strid
             OR
                 pc.strservicetype IS NULL AND st.strid = 'Printing')
            AND
                ss.lngserviceindex = pc.lngserviceindex
			AND
				pc.ysnremoved = false
            AND
                ss.strname         = ?
            AND
                pc.lngprojectindex = ?
        };

        $sth = $dbh->prepare_cached($query);

        my %col_types = (
            txtPrice      => [qw( category name  )],
            txtStockPrice => [qw( stock    stock )],
        );

        my $est = $r->param('ddmExport') eq 'Estimates';

        foreach my $col (keys %col_types) {
            $sth->execute(
                "$col$row->{intquantityindex}", $row->{lngprojectindex}
            );



            while (my $service = $sth->fetchrow_hashref) {
				my ($id, $name, $cat, $weight ) = $dbh->selectrow_array(q{
					SELECT strid, strname, strcategory, strWeight FROM tbl_Paper where lngindex = 
						(Select strValue FROM tbl_service_specifications where
							lngserviceindex = ? and strname = 'hdnPaperIndex' )::int
			}, undef, $service->{index});
				my $sheet_count = $dbh->selectrow_array( qq{
					SELECT strvalue FROM tbl_service_specifications WHERE
						lngserviceindex = ? and strName = 'hdnGrossSheetCount$row->{intquantityindex}'
					}, undef , $service->{index});
				$sheet_count = 1 if ! $sheet_count;
                my $x = $service->{ $col_types{$col}->[1] };

                my @new_line  = @SPL_LINE;
                $new_line[1]  = $order->{lngorderid} . '-' . $$line++;

                $new_line[2]  = 'ESTIMATE' if $est;

                $new_line[3]  = $order->{due_date};
                $new_line[4] = $col eq 'txtStockPrice' 
								 ?	configuration::get_value($log, $dbh, 'StockExportAccount') 
                			     :	configuration::get_value($log, $dbh, 'ServiceExportAccount');
#                $new_line[6] = $col eq 'txtStockPrice' 
#								 ?	configuration::get_value($log, $dbh, 'StockExportAccount') 
#                			     :	configuration::get_value($log, $dbh, 'ServiceExportAccount');
                $new_line[7]  = $service->{removed}  ? 0 : $service->{price} * -1;
                $new_line[9]  = $col eq 'txtStockPrice' ?  $name . ' ' . $weight : $service->{ $col_types{$col}->[1] };
                $new_line[11] = $col eq 'txtStockPrice' ? -1 * $sheet_count : -1;
                $new_line[12] = $service->{price};
                
                # For shipping we only charge fed tax.
                $new_line[17] = $service->{ $col_types{$col}->[0] } eq 'Shipping' ? 'G' :  $tax;
                $new_line[13] = $col eq 'txtStockPrice' 
								 ?	configuration::get_value($log, $dbh, 'StockExportAccount') 
                			     :	configuration::get_value($log, $dbh, 'ServiceExportAccount') . ":$service->{ $col_types{$col}->[0] }";
                $new_line[13] .= ':Sheet' if $col eq 'txtStockPrice';

				# Add description to Custom Line Items
                $new_line[9] =  $new_line[9] . " - " . $service->{desc} if $new_line[9] eq 'Custom Service';


                push(@results, invoice_array(@new_line));
            }
        }
    }
    return @results;
}

sub invoice_lines {
    my ($r, $dbh, $order, $contents, $seq) = @_;
	my $log = $r->log;

    my @resultset;
	
	# Find the Sales Rep for the order
	($order->{sales_rep}) = $dbh->selectrow_array( q{
		SELECT strFirstName || ' ' || strLastName FROM tbl_customer_users
		WHERE lnguserid = ( SELECT lngsalesperson FROM tbl_customer where lngcustomerid = ?)
	}, undef, $order->{lngcustomerid} );

	# TODO: Terms should be stored with the order.
	($order->{terms}) = $dbh->selectrow_array( qq{
		SELECT lngterms FROM tbl_customer_credit
		WHERE lngcustomerindex = ?
	}, undef, $order->{lngcustomerid} );

	# Due date is the date the invoice is due.
    # This is a change requested by A4. Will aslo be used
    # as the standard ( for now ).
	($order->{due_date}) = $dbh->selectrow_array( q{
		SELECT to_char(MAX(daterequired),'MM/DD/YYYY') FROM tbl_order_contents
        WHERE lngorderid = ?
	}, {}, $order->{lngorderid}, );

	($order->{pay_date}) = $dbh->selectrow_array( qq{
		SELECT to_char(
            MAX(daterequired) + '$order->{terms} days'::interval,
            'MM/DD/YYYY' 
        ) 
        FROM tbl_order_contents
        WHERE lngorderid = ?
	}, {}, $order->{lngorderid} );


    my $total = $order->{curtotalsale};

    my $tax   = $order->{curharmtax}                        ? 'H'
              : $order->{curfedtax} && $order->{curprovtax} ? 'S'
              : $order->{curfedtax}                         ? 'G'
              : $order->{curprovtax}                        ? 'P'
              :                                               'E';

    my @invoice_line  = @INVOICE_LINE;

    $invoice_line[1]  = $order->{lngorderid};
    $invoice_line[2]  = 'ESTIMATE' if $r->param('ddmExport') eq 'Estimates';
    $invoice_line[4]  = 'Estimates' if $r->param('ddmExport') eq 'Estimates';
    $invoice_line[3]  = $order->{due_date};

#    $invoice_line[6]  = configuration::get_value($log, $dbh, 'ServiceExportAccount');
    $invoice_line[7]  = $total;
    $invoice_line[8]  = $order->{lngorderid};
    $invoice_line[9]  = $order->{strcurrencyname};
    $invoice_line[12] = $order->{strcompanyname};
    $invoice_line[15] = $order->{strpostalcode};
    $invoice_line[16] = $order->{strcountry};
    $invoice_line[17] = $order->{pay_date};
    $invoice_line[18] = "Net $order->{terms} days";
    $invoice_line[19] = $order->{ysnfinished};
    $invoice_line[22] = $order->{dtmshipdate};
    $invoice_line[24] = $order->{sales_rep};
    $invoice_line[26] = $order->{strponumber};
    $invoice_line[29] = $order->{strshippingcompanyname};
    $invoice_line[32] = $order->{strshippingpostalcode};
    $invoice_line[33] = $order->{strshippingcountry};

    $invoice_line[5]  = $order->{strcompanyname}
                      . ':'
                      . $order->{lngorderid};

    $invoice_line[30] = $order->{strshippingaddress1}
                      . q{ }
                      . $order->{strshippingaddress2};

    $invoice_line[31] = $order->{strshippingcity}
                      . q{, }
                      . $order->{strshippingstate};

    $invoice_line[13] = $order->{straddress1}
                      . q{ }
                      . $order->{straddress2};

    $invoice_line[14] = $order->{strcity}
                      . q{, }
                      . $order->{strstate};

    push(@resultset, invoice_array(@invoice_line));

    # Add new function HERE
    my $line = 1;
    if ( $r->param('ddmExport') eq 'InvoicesSimple' ) {
        push(@resultset, simple_lines($r, $log, $dbh, $contents, $order, $tax, \$line));
    } else {
        push(@resultset, detail_lines($r, $log, $dbh, $contents, $order, $tax, \$line));
    }    



    my %tax_map = (
        curfedtax  => 'GST',
        curprovtax => 'PST',
        curharmtax => 'HST',
    );

    foreach my $tax (keys %tax_map) {
        if ($order->{$tax}) {
            my @new_line  = @SPL_LINE;
            $new_line[1]  = $order->{lngorderid} . '-' . $line++;
            $new_line[2]  = 'ESTIMATE' if $r->param('ddmExport') eq 'Estimates';
            $new_line[3]  = $order->{due_date};
#            $new_line[6] = configuration::get_value($log, $dbh, 'ServiceExportAccount') . ':Additional';
            $new_line[4]  = "$tax_map{$tax} Payable";
            $new_line[7]  = $order->{$tax} * -1;
            $new_line[9]  = "Total $tax_map{$tax}";
            $new_line[12] = $order->{$tax};
#            $new_line[13] = configuration::get_value($log, $dbh, 'ServiceExportAccount') . ':Additional';
            $new_line[24] = $tax_map{$tax};

            push(@resultset, invoice_array(@new_line));
        }
    }

    push (@resultset, invoice_array(qw( ENDTRNS )));

    return @resultset;
}

sub payment_lines {
    my ($dbh, $payment, $seq) = @_;

    my ($company_name) = $dbh->selectrow_array(q{
        SELECT
            strcompanyname
        FROM
            tbl_orders
        WHERE
            lngorderid = ?
        }, undef, $payment->{lngorderid}
    );

    my @return_array;

    my @payment_line  = @PAYMENT_LINE;
    my @spl_line      = @PAYMENT_SPL;

    $payment_line[1]  = $payment->{lngorderid};
    $payment_line[3]  = $payment->{payment_date};
    $payment_line[5]  = $company_name;
    $payment_line[7]  = $payment->{curamount};
    $payment_line[9]  = $payment->{strcurrencyname};

    $spl_line[1]      = $payment->{lngorderid} . '-1';
    $spl_line[3]      = $payment->{payment_date};
    $spl_line[5]      = $company_name;
    $spl_line[7]      = $payment->{curamount} * -1;
    $spl_line[14]     = $payment->{method};

    push (@return_array, payment_array(@payment_line));
    push (@return_array, payment_array(@spl_line    ));
    push (@return_array, payment_array(qw( ENDTRNS )));

    return @return_array;
}

sub initialise_drop_downs {
    my ( $r, $log, $dbh, $variable ) = @_;

    get_start_end_dates(
        $log, $dbh, $variable,
        $r->param('ddmStartYear')  || undef,
        $r->param('ddmStartMonth') || undef,
        $r->param('ddmStartDay')   || undef,
        $r->param('ddmEndYear')    || undef,
        $r->param('ddmEndMonth')   || undef,
        $r->param('ddmEndDay')     || undef,
    );

    my ($start) = configuration::get_value($log, $dbh, 'startYear') || 2003;

    my %sql_map = (
        ddmCustomers  => q{ SELECT
                                lngCustomerID, strCompanyName
                            FROM
                                tbl_Customer
                            ORDER BY
                                LOWER(strCompanyName)         },

        ddmServices   => q{ SELECT
                                lngIndex, strName
                            FROM
                                tbl_Service_Types
                            ORDER BY
                                LOWER(strName)                },

        ddmEmployees  => q{ SELECT
                                lngUserID,
                                strFirstName || ' ' ||
                                strLastName
                            FROM
                                tbl_Customer_Users
                            WHERE
                                chrType IN ('E', 'A')
                            ORDER BY
                                LOWER(strFirstName)           },

        ddmEstimator  => q{ SELECT
                                lngUserID,
                                strFirstName || ' ' ||
                                strLastName
                            FROM
                                tbl_Customer_Users
                            WHERE
                                chrType IN( 'E', 'A')
                            ORDER BY
                                LOWER(strFirstName)           },

        ddmEquipment  => q{ SELECT
                                lngIndex, strName
                            FROM
                                tbl_Equipment
                            ORDER BY
                                LOWER(strName)                },

		ddmDivision	  => q{ SELECT
								id, name
							FROM 
								division
						   	ORDER BY
								LOWER(name)					 }
    );

    foreach my $drop_down ( keys %sql_map ) {
        my $columns = { Columns => [ 1, 2 ] };

        my $results = $dbh->selectcol_arrayref(
            $sql_map{ $drop_down }, $columns
        );

        $variable->{$drop_down} = make_drop_down(
            $results, $r->param($drop_down)
        );
    }

    $variable->{ 'ddmStatus' . $r->param('ddmStatus') }
        = "selected='selected'";

    foreach my $total ( 1 .. 3 ) {
        $variable->{"dblTotal$total"} = $r->param("dblTotal$total");
    }
}

sub display_accounting_reports {
    my ($r, $log, $dbh, $variable) = @_;

    for (qw(  ddmExportOptions ddmExport ddmFormat )) {
        $variable->{$_ . $r->param($_)} = "selected='selected'"
            if $r->param($_);
    }

    if (!$r->param('ddmExportOptions')) {
        $variable->{ddmExportOptionsAll} = "checked='checked'";
    }

    if ($r->param('ddmExport') eq 'Payments') {
        $variable->{ArrayOfEntries} = [
            { width => 100, entry => 'Payment ID',      },
            { width =>  50, entry => 'Amount',          },
            { width => 100, entry => 'Date',            },
            { width => 200, entry => 'Company',         },
            { width => 100, entry => 'Method',          },
            { width => 150, entry => 'Currency',        },
            { width => 150, entry => 'Last Exported',   },
        ];

        my $query = q{
            SELECT
                lngindex                             AS value1,
                lngindex                             AS value2,
                strcurrencysymbol || curamount       AS value3,
                TO_CHAR(dtmdate, 'YYYY-MM-DD')       AS value4,
                strcompanyname                       AS value5,
                strmethod                            AS value6,
                strcurrencyname                      AS value7,
                TO_CHAR(dtmoutputdate, 'YYYY-MM-DD') AS value8
            FROM tbl_Payments, tbl_Customer
            WHERE tbl_Payments.lngcustomerindex = tbl_Customer.lngcustomerid
            AND dtmDate BETWEEN ? AND ?
        };

        my @bind_params = @$variable{qw( StartDate EndDate )};

        if ($r->param('ddmCustomers')) {
            $query .= 'AND lngcustomerindex = ?';
            push @bind_params, $r->param('ddmCustomers');

        }

        $variable->{ArrayOfCompanies} = $dbh->selectall_arrayref(
            $query, { Slice => {} }, @bind_params
        );
    }
    else {
        my ($addition, $bind_params) = get_order_criteria_sql(
            $r, $dbh, @{ $variable }{qw( StartDate EndDate )}
        );

        $variable->{ArrayOfEntries} = [
            { width => 100, entry => 'Order ID',        },
            { width =>  50, entry => 'Total',           },
            { width => 100, entry => 'Date',            },
            { width => 200, entry => 'Ship to Company', },
            { width => 100, entry => 'Status',          },
            { width => 150, entry => 'Last Modified',   },
            { width => 150, entry => 'Last Exported',   },
        ];

        my $query = q{
            SELECT
                lngOrderID                             AS value1,
                lngOrderID                             AS value2,
                curTotalSale                           AS value3,
                TO_CHAR(dtmOrderDate,    'YYYY-MM-DD') AS value4,
                strShippingCompanyName                 AS value5,
                strStatus                              AS value6,
                TO_CHAR(dtmModifiedDate, 'YYYY-MM-DD') AS value7,
                TO_CHAR(dtmExportDate,   'YYYY-MM-DD') AS value8
            FROM tbl_orders
            WHERE ysnfinished
              AND strstatus <> 'Incomplete'
        };

        if ($addition) {
            $query .= "AND $addition";
        }

        $variable->{ArrayOfCompanies} = $dbh->selectall_arrayref(
            $query, { Slice => {} }, @{ $bind_params }
        );
    }

    return;
}

sub get_payments_sth {
    my ($r, $dbh, $start_date, $end_date) = @_;

    my $query = q{
        SELECT
            *,
            TO_CHAR(dtmDate, 'MM/DD/YYYY') AS payment_date
        FROM
            tbl_Payments
    };

    my ($addition, $binds) = get_payment_criteria_sql(
        $r, $dbh, $start_date, $end_date
    );

    my $sth = $dbh->prepare("$query WHERE $addition");
    my $n   = 0;

    $sth->bind_param(++$n, $_) for @{ $binds };
    $sth->execute();

    return $sth;
}

sub get_payment_criteria_sql {
    my ($r, $dbh, $start_date, $end_date) = @_;

    my @ands        = ('dtmDate BETWEEN ? AND ?');
    my @bind_params = ($start_date, $end_date);

    if ($r->param('ddmCustomers')) {
        push @ands,        'lngcustomerindex = ?';
        push @bind_params, $r->param('ddmCustomers');
    }

    return (join(' AND ', @ands), \@bind_params);
}

sub get_orders_sth {
    my ($r, $dbh, $start_date, $end_date) = @_;

    my $query = q{
        SELECT
            *,
            TO_CHAR(dtmOrderDate,    'MM/DD/YYYY')          AS order_date,
            TO_CHAR(dtmModifiedDate, 'YYYY-MM-DD HH:MI:SS') AS   mod_date,
            TO_CHAR(dtmExportDate,   'YYYY-MM-DD HH:MI:SS') AS   exp_date
        FROM
            tbl_Orders
    };

    my ($addition, $binds) = get_order_criteria_sql(
        $r, $dbh, $start_date, $end_date
    );

    my $sth = $dbh->prepare("$query WHERE $addition");

    my $n = 0;

    $sth->bind_param(++$n, $_) for @{ $binds };
    $sth->execute();

    return $sth;
}

sub get_order_criteria_sql {
    my ($r, $dbh, $start_date, $end_date) = @_;

    my @ands        = ('dtmOrderDate::date BETWEEN ? AND ?');
    my @bind_params = ($start_date, $end_date);

    if ($r->param('ddmStatus')) {
        push @ands,        'strStatus = ?';
        push @bind_params, $r->param('ddmStatus');
    }

    if ($r->param('ddmCustomers')) {
        push @ands,        'strCompanyName = ?';
        push @bind_params, $dbh->selectrow_array(q{
            SELECT
                strCompanyName
            FROM
                tbl_Customer
            WHERE
                lngCustomerID = ?
            }, undef, $r->param('ddmCustomers')
        );
    }

    return (join(' AND ', @ands), \@bind_params);
}

sub invoice_array { remap_array(scalar(INVOICE_HEADER) - 1, @_) }
sub payment_array { remap_array(scalar(DEFAULT_TRNS)   - 1, @_) }

sub remap_array {
    my ($size, @array) = @_;
    $#array = $size;
    my @result = map { defined $_ ? $_ : '' } @array;
    return \@result;
}

sub inventory {
    my ( $r, $log, $dbh, $variable ) = @_;

    initialise_drop_downs( $r, $log, $dbh, $variable );

    my $query = q{
        SELECT
			i.id, 		lngprojectindex, 	strcompanyname, 
			l.name, 	i.strdescription, 	lngcheckinquantity,
			obsolete,	revised, 			lngremainingquantity, 
			lngremainingquantity * unit_price as value
        FROM
            tbl_inventory i , inventory_locations l, tbl_Customer c
        WHERE
            i.dtmcheckindate::Date BETWEEN ? AND ?
        AND
            i.locationid = l.id
        AND
            c.lngcustomerid = i.lngcustomerid
			
    };

    my @bind_params = ( $variable->{StartDate}, $variable->{EndDate} );

    my %sql_map = (
#        'tbl_Orders.strStatus'        => 'ddmStatus',
        'i.lngCustomerID'    => 'ddmCustomers',
#        'tbl_Customer.lngSalesPerson' => 'ddmEmployees',
    );

    foreach my $col ( keys %sql_map ) {
        my $param = $r->param($sql_map{ $col });
        if ($param) {
            $query .= "    AND $col = ? ";
            push(@bind_params, $param);
        }
    }

    $query .= q{
		ORDER BY 1,2
	};

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    if ( $r->param('btnFunction') eq 'Download in CSV Format' ) {
        my @data;

        while (my $row = $sth->fetchrow_hashref) {
            push(@data, @$row{qw( id lngprojectindex strcompanyname name strdescription lngcheckinquantity lngremainingquantity value obsolete revised )});
        }

		my $header = ['Inventory ID', 'Project ID', 'Company', 'Location', 'Project Name', 
					  'Quantity Checked In','Quantity Remaining', 'Case $ x Quantity Cases Remaining', 'Obsolete', 'Revised'];
        misc::export_csv(
            $r, $log, $variable, 'inventory_report.csv', $header, \@data
        );
    }
    else {
        my $results = $sth->fetchall_arrayref( {} );

        $variable->{ReportTotal}   = sum map { $_->{cursale} } @{ $results };
        $variable->{ReportBalance} = sum map { $_->{balance} } @{ $results };

        $variable->{inventory} = $results;
use Data::Dumper;
print STDERR "INVENTORY RESULTS " , Dumper($results);
    }
}

sub inventory_usage {
    my ( $r, $log, $dbh, $variable ) = @_;

	my @t = localtime();

#Get 1st & last day of the current month;
	my $date = DateTime->new(
		year  => $t[5]+1900,
		month => $t[4]+1,
		day   => 1,
	);

	my $date2 = $date->clone;
	$date2->add( months => 1 )->subtract( days => 1 );

print STDERR "HAVE DATE START ", $date->ymd('-'), "\n";
print STDERR "HAVE DATE START ", $date2->ymd('-'), "\n";

	$variable->{start_date} = $date->ymd('-')  unless $variable->{start_date}; 
	$variable->{end_date}   = $date2->ymd('-') unless $variable->{end_date}; 



	if ( $r->param('ObsoleteReport') ) {
		return obsolete_report( $r, $log, $dbh, $variable );
	}


    initialise_drop_downs( $r, $log, $dbh, $variable );

	return unless $r->param('MonthlyUsage');


	my $sth = $dbh->prepare(q{
		SELECT distinct i.id, itemid, strdescription FROM tbl_inventory i, inventory_specs s
		WHERE i.id = s.id AND i.lnginventoryindex = 1087
	});


	my @bind_params;
    $sth->execute(@bind_params);
    my $results = $sth->fetchall_arrayref( {} );


	my $ytd = $dbh->prepare(q{
		SELECT sum(lngcheckoutquantity) as qty 
		FROM tbl_inventory_checkout c, tbl_inventory i
		WHERE i.id = ? 
		And i.lnginventoryindex = c.lnginventoryindex
		AND dtmcheckoutdate BETWEEN ? AND  ?
	});

	my $start = $t[5]+1900 . '-' . ($t[4]+0) . '-1'; 

	map {
		my @months;
		my $mon_avg = 0;
		foreach my $i (1..13) {
			my $sstart = $i . ' month';
			my $send = $i-1 . ' month';


			my $sql = qq{
				SELECT 1 as id, to_char(?::timestamp - interval '$sstart', 'Mon') as month,
					   sum(lngcheckoutquantity) as qty 
				FROM tbl_inventory_checkout c, tbl_inventory i
				WHERE i.id = ? 
				And i.lnginventoryindex = c.lnginventoryindex
				AND dtmcheckoutdate BETWEEN ?::timestamp - interval '$sstart' AND ?::timestamp - interval '$send'
			};

			my $usage = $dbh->prepare($sql);

			$usage->execute($start,  $_->{id}, $start,  $start, );


			my $mon = $usage->fetchrow_hashref();

			$mon_avg += $mon->{qty} unless $i == 13 or !$mon->{qty};

			push @months,  $mon;

print STDERR "ADDING  Month FROM ID: $_->{id} " . $mon_avg . " $mon->{qty} Start: $start $sstart - $send QTY: $mon->{qty} \n";

			$_->{months} = \@months;
	
		}
print STDERR "ADDING  Month: " . $mon_avg . "\n";
		$ytd->execute( $_->{id},($t[5] + 1900) .'-01-01', $start);
		$_->{ytd} = $ytd->fetchrow_array();

		$ytd->execute( $_->{id},($t[5] + 1899) .'-01-01', ($t[5]+1899) . '-' . ($t[4]+0) . '-1');
		$_->{pytd} = $ytd->fetchrow_array();

		$_->{dytd} = ($_->{ytd} / $_->{pytd} - 1) * 100 if $_->{pytd};
		$_->{mon_avg} = $mon_avg / 12;
		$_->{run_mon_avg} = $mon_avg;
		$_->{unit} = 'EA/1';
		$_->{current_usage} = $_->{months}[0]->{qty};


	} @{$results};
	my $up = 1;

		my @data=();

        foreach my $row  (@{$results}) {
            my @rd = @$row{qw( itemid strdescription b b b b unit mon_avg ytd pytd dytd run_mon_avg )};
            push @data, @rd;
            push @data, 'CurrentPeriod', @$row{qw(current_usage b b)}, 'Estimated Dollars Used', '', '',
						$rd[7] * $up,
						$rd[8] * $up,
						$rd[9] * $up,
						($rd[9] - $rd[8]) * $up,
						$rd[11] * $up
			;
			map {
				push @data, $_->{month} unless $_->{id} == 1;
			} @{$row->{months}};
			map {
				push @data, $_->{qty} unless $_->{id} == 1;
			} @{$row->{months}};
        }

		my $header = ['Item No.','Desciprtion','','','','','Unit','Avg Mo Usage','YTD Usage', 'Prev YTD', 'YTD % +/- On Hand', '12 Mo Avg Uage'];

        misc::export_csv(
            $r, $log, $variable, 'usage_report.csv', $header, \@data
        );


}
sub obsolete_report {
	my ($r, $log, $dbh, $var) = @_;

	my $query = q{
		SELECT 
			i.obsolete_date AS "Obsolete Date",
			i.id::text AS "Inventory ID", 
			ins.itemid::text AS "Item ID", 
			i.lngprojectindex::text AS "Project ID", 
			i.strdescription AS "Project Reference",
			i.obsolete_qty::text AS "Quantity",
			'EA/1' AS "Unit",
			i.unit_price::text AS "Unit Price",
			(i.obsolete_qty * i.unit_price)::text AS "Value $",
			CASE WHEN i.obsolete THEN 'True' END AS "Obsolete",
			CASE WHEN i.revised THEN 'True' END AS "Revised"

		FROM
			tbl_inventory i,
			inventory_specs ins
		WHERE 
			i.complete = 'TRUE'
			AND (obsolete OR revised )
			AND i.id = ins.id
			AND i.lngcustomerid = ?
			AND obsolete_date BETWEEN ? AND ?
	};

    my @bind_params = ($var->{cust_id}, $r->param('start_date'), $r->param('end_date'));

    $query .= q{
		ORDER BY 1,2
	};

    my $sth = $dbh->prepare($query);
       $sth->execute(@bind_params);

    my @data = ('Obsolete Date', 'Inventory ID','Item ID', 'Project ID', 'Project Reference', 'Quantity', 'Unit', 'Unit Price', 'Value $', 'Obsolete', 'Revised');

    while (my $row = $sth->fetchrow_arrayref) {
        push(@data, @{$row});
    }

	my @t = localtime();
	my $today =  ($t[4]+1) . '-' . $t[3] . '-' . ($t[5]+1900);
my $header = [ $today, 'Obsolete Report','','','Prepared For:',$var->{user}{company}{name},'','','','',''];
    misc::export_csv(
        $r, $log, $var, 'obsolete_report.csv', $header, \@data
    );
use Data::Dumper;
print STDERR Dumper($var);
	

}
sub shipping_report {
	my ($r, $log, $dbh, $var) = @_;

	my @data;

	my $orders = $dbh->selectall_arrayref(q{
		SELECT lngprojectindex, tbl_orders.lngorderid, intquantityindex
		 FROM tbl_orders, tbl_order_contents 
		 WHERE tbl_orders.lngorderid = tbl_order_contents.lngorderid
		 AND dtmorderdate::date BETWEEN
		 now()::date - interval '1 day' and now()::date - interval '1 day'
		 AND ysnfinished
		 AND lngcustomerid <> 1
	});

print STDERR "SHIPPING: ", Dumper($orders);

	foreach my $order (@{$orders}) {
		my $pid 	 = shift @{$order};
		my $order_id = shift @{$order};
		my $qid 	 = shift @{$order};
		next unless $qid;

		my $desc = $dbh->selectrow_array(q{
			SELECT strprojectreference FROM tbl_projects WHERE lngprojectindex = ?
		}, undef, $pid);

		my $cust_name = $dbh->selectrow_array(q{
			SELECT strcompanyname FROM tbl_orders WHERE tbl_orders.lngorderid = ?
		}, undef, $order_id);
		
		my @ships = eprint::Service::Shipping::get_ship_info($r, $log, $dbh, $pid, $qid);

		map {
			push @data, [ $_->{boxes}, $_->{weight}, $order_id, 
						  $pid, $desc, $_->{per_box}, $cust_name, $_->{address}];
		} @ships;




	
	}

print STDERR "SHIP DATA:  \n", Dumper(@data);

	my $csv = Text::CSV_XS->new({ eol => "\n" });

	my $output = "Boxes, Weight, Order ID, Project ID, Project Name, Qty per box"
				.", Customer Name, Address\n";

	foreach my $line (@data) {
		$csv->combine(@{ $line });
		$output .= $csv->string();
	}
	shipping_email($r, $log, $dbh, $output);


}

sub shipping_email {
	my ($r, $log, $dbh, $report ) = @_;

	my $email_template = misc::load_file($r, '/email/email_template.html');

	my %info;
    $info{'ReplacementText'} = 
		"<!--#include virtual=\"/email/content/shipping_report.html\"-->";

    #$info{'domain'} = configuration::get_value($log, $dbh, 'domain');
    $info{'siteURL'} = "http://" . $r->hostname;

    #$_ = ssi::variable_substitution($r, $log, $dbh, $email_template, \%info);

    $_ = encode_qp(ssi::variable_substitution($r, $log, $dbh, $email_template, \%info));
	

    my @body = ('', $_, 'text/html', 'quoted-printable');

    my %mail = (
          SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          TO      => configuration::get_value($log, $dbh, 'ShippingNotification'),
          SUBJECT => 'Shipping Report',
    );

	my @attach = ('shipping_report.csv', $report, 'text/csv','quoted-printable');

    misc::send_email_with_attachment($r, $log, \%mail, @body, @attach); 

}


sub national_report {
	my ($r, $log, $dbh, $var) = @_;

	my @date = localtime(time);
	my $dom = $date[3];

	my $run_dates = $dbh->selectrow_array(q{
		SELECT strconfigdata FROM tbl_configuration WHERE strconfigtitle='NationalFlyerDates'

	});

	my @run = split(',',$run_dates);

	return unless grep { $_ == $dom } @run; 

	my $cust = $dbh->selectcol_arrayref(q{
		SELECT notification_email FROM tbl_customer 
		WHERE  nationalcredit > 0
	},{ SLICE => {} });

	use Data::Dumper;
	print STDERR "CUST " , Dumper($cust);
	map {
		national_email($r, $log, $dbh, $var, $_);
	} @{$cust};
}

sub national_email {
	my ($r, $log, $dbh, $var, $email ) = @_;

	my $email_template = misc::load_file($r, '/email/email_template.html');

	my %info;
    $info{'ReplacementText'} = "<!--#include virtual=\"/email/content/national_notification.html\"-->";

    $info{'siteURL'} = "http://" . $r->hostname;

    $_ = encode_qp(ssi::variable_substitution($r, $log, $dbh, $email_template, \%info));

    my @body = ('', $_, 'text/html', 'quoted-printable');

    my %mail = (
          SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
          FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
          TO      => $email,
          SUBJECT => 'National Print Run',
    );

    misc::send_email_with_attachment($r, $log, \%mail, @body);

}





1;
