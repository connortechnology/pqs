package eprint::employee_project;
use strict;

use Apache2::Const qw(OK);
use sql qw(:common);
use ssi ();
use misc;
use Mail::Sendmail;
use MIME::QuotedPrint;

require eprint::project;
require eprint::print;
require eprint::docket;

# List ordered projects for employees (with some search ability).
sub project_list {
    my ($r, $log, $dbh, $variable) = @_;
    my ($temp, @projectTypes, @products);

    my $customer_filter = $r->param('ddmCustomers');
    my $category_filter = $r->param('ddmCategorys');
    my $status_filter   = $r->param('ddmStatus') || 'In Production';
	
	$variable->{PROJECTS} = [];

    if ( $r->param('btnFunction') eq 'Submit' ) {
		map { complete_project($r, $dbh, $_, $variable) } $r->param('complete');
        
		foreach my $key ( $r->param() ) {
            if ( $key =~ /ddmPriority(\d*)/ ) {
                sql::update( $log, $dbh, 'tbl_Projects', 
					"lngProjectIndex = '$1'", 'lngPriority', $r->param($key) );
			} elsif( $key =~ /ddmDay-(\d*)/) {
				#  sql::update( $log, $dbh, 'tbl_order_contents', 
				#		"lngProjectIndex = '$1'", 'dateRequired', 
				#							  $r->param("ddmMonth-$1") . '/' .
				#							  $r->param("ddmDay-$1") . '/' .
				#							  $r->param("ddmYear-$1")
				#	);
					
			}
		}
    }

    ssi::get_start_end_dates( $log, $dbh, $variable, 
            ( $r->param('ddmStartYear') or undef ),
            ( $r->param('ddmStartMonth') or undef ),
            ( $r->param('ddmStartDay') or undef ),
            ( $r->param('ddmEndYear') or undef ),
            ( $r->param('ddmEndMonth') or ( (localtime(time))[4] == 11 ? 0 : (localtime(time))[4]+2 ) ),
            ( $r->param('ddmEndDay') or undef ),
            );

    $$variable{'ddmStatus'.$r->param('ddmStatus')} = 'SELECTED';

    # get customer list.
    $_ = "SELECT lngCustomerID, strCompanyName FROM tbl_Customer ORDER BY lower(strCompanyName)";
    $$variable{'ddmCustomers'} = ssi::fill_drop_down ($log, $dbh, $_, $customer_filter );
    $_ = "SELECT strName, strName FROM tbl_Service_Categories ORDER BY strName";
    $$variable{'ddmCategorys'} = ssi::fill_drop_down ($log, $dbh, $_, $category_filter );

	my $division = $dbh->selectrow_array(q{
		SELECT division FROM tbl_customer WHERE lngcustomerid = ?
	}, undef, $variable->{cust_id});

print STDERR "HAVE DIVSION: $division \n";

    my $sql = "SELECT lngProjectIndex FROM tbl_Projects, tbl_customer 
			   WHERE tbl_projects.lngcustomerid = tbl_customer.lngcustomerid
			   AND tbl_customer.division = $division 
			   \n";

	if ( $status_filter eq 'Quoted' ) {
		$sql .= " AND lngprojectindex IN  (SELECT lngprojectindex FROM tbl_Quotes q, tbl_Quote_Details d
					        WHERE q.lngquoteid=d.lngquoteid 
					        AND dtmQuoteDate BETWEEN date('$$variable{'StartDate'}') 
					                 AND date('$$variable{'EndDate'}')
						   ) \n";
#    } elsif ( $status_filter eq 'All' ) {
#		$sql .= " AND dtmcreationdate BETWEEN date('$$variable{'StartDate'}') 
#					                 AND date('$$variable{'EndDate'}'
#						   ) \n";
	} else {
		$sql .= "AND to_date(delivery_date(lngprojectindex), 'MM/DD/YYYY')
					BETWEEN date('$$variable{'StartDate'}') AND date('$$variable{'EndDate'}')\n";
	
	}
    $sql .= "AND strStatus = 'Complete' \n"                                 if $status_filter eq 'Complete';
    $sql .= "AND strStatus = 'In Production'\n"                             if $status_filter eq 'In Production';
    $sql .= "AND (strStatus = 'Complete' OR strStatus = 'In Production')\n" if ! $status_filter;
    $sql .= "AND lngCustomerID = '$customer_filter'\n"                      if $customer_filter ne '';
    $sql .= "ORDER BY lngPriority DESC, delivery_time(lngprojectindex)::timestamp";

print STDERR "HAVE SQL: $sql \n";
    my @projects = sql::sql_statement( $log, $dbh, $sql );
   	my @priorities;
    my $tmp= $dbh->selectall_arrayref(q{ SELECT id, name FROM priority },undef,);

	my @tmp;
	while ( my $elem  = shift @$tmp){
		push @priorities, shift @$elem;
		push @priorities, shift @$elem;
	}

    while ( @projects ) {
        my $pid = shift @projects;
        $_ = "SELECT MAX(lngOrderID) FROM tbl_Order_Contents WHERE lngProjectIndex='$pid'";
        my ( $order_id ) = sql::sql_statement( $log, $dbh, $_ );

        my ( $name, $cust_id, $date, $status, $priority, $comp_date ) = sql::sql_statement( $log, $dbh, qq{
            SELECT SUBSTR(strProjectReference,0,50),
                   ( SELECT strCompanyName 
                     FROM tbl_Customer 
                     WHERE tbl_Customer.lngCustomerID = tbl_Projects.lngCustomerID
                   ),
					delivery_date(lngprojectindex),
                   strStatus, 
                   lngPriority,
					completion_date
            FROM tbl_Projects, priority t
            WHERE t.id            = lngpriority  
              AND lngProjectIndex = '$pid'
            ORDER BY strstatus, lngpriority DESC
        });

        if ( $category_filter ne '' ) {
            $log->debug(" ************* STARTING CATEGORY FILTER : $category_filter ******************");
            if ( $category_filter eq 'Printing' ) {
                $log->debug(" ************* STARTING PROJECT TYPE******************");
                $_ = "SELECT DISTINCT lngProjectIndex FROM tbl_Service_Specifications WHERE ".
                    " lngProjectIndex='$pid' AND strName='ProjectType' ";
            #    ($pid) = sql::sql_statement( $log, $dbh, $_ );
            } else {
            $log->debug(" ************* STARTING PRODUCT TYPE******************");
                if ( ! @products ) {
                    $_ = "SELECT strID FROM tbl_Service_Types WHERE strCategory='$category_filter'";
                    @products = sql::sql_statement( $log, $dbh, $_ );
                }

                $_ = "SELECT DISTINCT lngProjectIndex FROM tbl_Service_Specifications WHERE lngProjectIndex='$pid' ".
                    " AND strName='ServiceType' AND strValue IN (SELECT strID FROM tbl_Service_Types WHERE strCategory='$category_filter')";
                ($pid) = sql::sql_statement( $log, $dbh, $_ );
            }
        }

		my ($date) = delivery_date( $dbh, $pid);

        if ( $pid ne '' ) {
            push @{$$variable{'PROJECTS'}}, $order_id, $pid, $name, $cust_id, $date, $status, 
					$priority, ssi::make_drop_down( \@priorities, $priority ), $comp_date;
        }


		# Used for editing dates on schedule page?
		my ($day, $month, $year, $time) = $date =~ /(\d\d)\/(\d\d)\/(\d{4})/;

		$variable->{__FillInForm}{"ddmMonth-$pid"}  = $month;
		$variable->{__FillInForm}{"ddmYear-$pid"}   = $year;
		$variable->{__FillInForm}{"ddmDay-$pid"}    = $day;
		$variable->{__FillInForm}{"ddmTime-$pid"}   = $time;
    }
	$variable->{__FillInForm}{"ddmStatus"}   =  $r->param('ddmStatus') || 'In Production';

}
	
sub delivery_date {
	my ( $dbh, $pid ) = @_;

	my $date = $dbh->selectrow_array(q{SELECT delivery_time(?)}, undef, $pid);

	return ($date);


}

sub complete_project {
	my ( $r, $dbh, $pid, $variable ) = @_;

		my $log = $r->log;


		$dbh->do(q{ UPDATE tbl_projects set dtmshipdate = NOW() WHERE lngprojectindex = ? } , {} , $pid );
		$dbh->do(q{ UPDATE tbl_projects set completion_date = NOW() WHERE lngprojectindex = ? } , {} , $pid );

		sql::update( $log, $dbh, 'tbl_Project_Contents', "lngProjectIndex=$pid", 'strStatus', 'Complete' );

		# sql::update( $log, $dbh, 'tbl_Projects',         "lngProjectIndex=$pid", 'strStatus', 'Complete' );


		
		my $p = new PQS::Object::project($pid);
		$p->update_status();

		#Update status should do allow of these things inlcluding update order.
		#my $order_id = scalar $dbh->selectrow_array(q{
		#	SELECT lngorderid FROM tbl_order_contents where lngprojectindex = ? LIMIT 1
		#}, undef, $pid );

		#mark_order($dbh, $order_id);
		#

# Disable for safway for now.
#        send_project_complete_email($r, $dbh, $pid, $order_id, $$variable{cust_id});


		$variable->{complete} = 1;
		$dbh->do(q{UPDATE tbl_inventory SET complete = true WHERE lngprojectindex = ?}, undef, $pid);
}

# Display a basic project view where employees can mark the project as
# complete or view the docket.
sub view_project {
	my ( $r, $log, $dbh, $variable ) = @_;
	my $temp;

	my $pid = $variable->{ProjectIndex} = $r->param('ProjectIndex');


    return misc::error($log, $dbh, $variable, 'Project', "Project ($pid) not found.")
        unless $dbh->selectrow_array(q{
                   SELECT true FROM tbl_projects WHERE lngprojectindex = ?
               }, undef, $pid);


	my $order_id = $variable->{'Order_Id'} = $r->param('order_id');

    $order_id = scalar $dbh->selectrow_array(q{
        SELECT lngorderid FROM tbl_order_contents where lngprojectindex = ? LIMIT 1
    }, undef, $pid ) unless $order_id;

    # Old complete project stuff.
    if ( $r->param('btnFunction') eq 'Complete' ) {
		complete_project($r, $dbh, $pid, $variable);
			
	}

    # Populate $variable with the header information and all the display
    # project service and material pricing.   
    $variable->{HeaderInfo} = eprint::docket::header_info($log, $dbh, $pid);
    eprint::print::display_project( $log, $dbh, $variable, $pid );

	$$variable{qtyIndex} = scalar $dbh->selectrow_array(q{
		SELECT intquantityindex
		FROM tbl_order_contents
		WHERE lngprojectindex = ?
	          AND lngorderid = ?
	},undef, $pid,$order_id);
	
	$variable->{inventory_id} = $dbh->selectrow_array(q{
		SELECT id FROM tbl_inventory WHERE lngprojectindex = ?
	}, undef, $pid);

    
    return OK;
}

# Notify the user the given project has been produced.
sub send_project_complete_email {
    my ($r, $dbh, $pid, $order, $cust) = @_;

    my $log = $r->log;

	my $cust_email = $dbh->selectrow_array(q{
		SELECT stremail FROM tbl_orders WHERE lngorderid = ?
	}, undef, $order);

    my %hash = (
        cust_id  => $cust,
        qtyIndex => scalar $dbh->selectrow_array(q{
                        SELECT intquantityindex
                        FROM tbl_order_contents
                        WHERE lngprojectindex = ?
                          AND lngorderid = ?
                     }, undef, $pid, $order),
    );

    eprint::docket::summary_display(
        $r, $log, $dbh, \%hash, $pid, undef, $hash{qtyIndex} 
     );

    eprint::print::display_project( $log, $dbh, \%hash, $pid );

    $hash{ReplacementText} 
        = qq{ <!--#include virtual="/email/forms/project.html"--> };
    my $template = misc::load_file($r, '/email/email_template.html');

    my $email = encode_qp(ssi::variable_substitution($r, $log, $dbh, $template, \%hash));
    my @body = ('', $email, 'text/html', 'quoted-printable');
    my %mail = (
        SMTP	=> configuration::get_value($log, $dbh, 'Mail Server'),
        FROM	=> configuration::get_value($log,$dbh, 'ProjectCompletionEmail'),
        TO	    => configuration::get_value($log, $dbh, 'ProjectCompletionEmail'),
        SUBJECT => "Project #$pid Completed",
    );
    misc::send_email_with_attachment($r, $log, \%mail, @body);

    # Temporary fix to prevent different mime bondary strings being used
    # in the body.    
    delete $mail{BODY};

	$mail{TO} = $cust_email;
    misc::send_email_with_attachment($r, $log, \%mail, @body);

	$dbh->do(q{
		UPDATE tbl_inventory SET complete = true where lngprojectindex = ?
	}, undef, $pid); 

    return 1;
}

# Marks an order as 'Paid' or 'Complete' based on project completion and
# payment history.
sub mark_order {
    my ($dbh, $order) = @_;
    # Check to see if the order is complete. Note: Custom order line itesms
    # are assumed to always be complete.
    my $is_complete = $dbh->selectrow_array(q{
        SELECT count(o.*) = 0 
        FROM tbl_order_contents o, tbl_projects p
        WHERE p.lngprojectindex = o.lngprojectindex
          AND p.strstatus <> 'Complete'
          AND o.lngorderid = ?
    }, undef, $order);

    return unless $is_complete;

    # Sum the payments on that order against what is owed. 
    my $payments = $dbh->selectrow_array(q{
        SELECT SUM(curamount) FROM tbl_payments WHERE lngorderid = ?
    }, undef, $order);

    my $total = $dbh->selectrow_array(q{
        SELECT curtotalsale FROM tbl_orders WHERE lngorderid = ?
    }, undef, $order);
    
    # If it's paid for mark it as such, otherwise it's just complete.
    my $status = $payments >= $total ? 'Paid' : 'Complete';

    $dbh->do(q{
        UPDATE tbl_orders SET strstatus = ? WHERE lngorderid = ?
    }, undef, $status, $order);

    return 1;
}

1;
