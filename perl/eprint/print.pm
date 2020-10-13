package eprint::print;
use strict;
use utf8;

use Apache2::Const     qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc.
use Apache2::Util;
use Data::Dumper;
use List::Util            qw(sum);
use POSIX                 qw(ceil);
use Symbol                qw(qualify_to_ref);

use eprint::service       qw(:all);
use eprint::project       qw(:common :multipage :pricing :state has_pdf_template);
use sql                   qw(:common);
use eprint::docket        ();

require configuration;
require eprint::print_project;
require eprint::customer;
require PQS::model::change_order;

sub view_services {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

    my $pid = $r->param('ProjectIndex') 
           || $r->param('pid') 
		   || $variable->{param}{pid} #used by dashboard.
           || continue_project($dbh, $variable->{user_id});
       $pid =~ tr/0-9//cd;

	print STDERR "VIEW PROJECT: $pid \n";

	if ( $r->param('start') && $r->param('end') ) {
		custom_sort( $dbh, $pid, $r->param('start') ,  $r->param('end') );

	}
	

print STDERR "START VIEW SERVICES :  $variable->{edit} ************************* \n\n";

	#Custom Line Item Edit
   	if ( $r->param('edit') and $variable->{user_type} =~ /^[AE]$/ ) {
		my $sid =  $r->param('edit');
		$variable->{edit} = $sid;

		 my %specs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $sid);
		$variable->{custom_service} = \%specs;
		$variable->{__FillInForm}{hide_docket} = $specs{hide_docket};
	}


print STDERR "START VIEW SERVICES :  $variable->{edit} ************************* \n\n";
	my $qtys = [0,0,0];


#### CUSTOM CODE SECTION ***********
	my ($q1, $q2, $q3, $digifed) = $dbh->selectrow_array(q{
		SELECT intQuantity1, q2, q3, digifed FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	if ( $q2 ) {
		$dbh->do(q{
			UPDATE tbl_projects set q2 = NULL WHERE lngprojectindex = ?
		},undef,$pid);
		$qtys->[0] = $q2;
		eprint::print_project::add_qty($r, $log, $dbh, $cookie, $variable, $pid, $qtys);
	}
	if ( $q3 ) {
		$dbh->do(q{
			UPDATE tbl_projects set q3 = NULL WHERE lngprojectindex = ?
		},undef,$pid);
		$qtys->[0] = $q3;
		eprint::print_project::add_qty($r, $log, $dbh, $cookie, $variable, $pid, $qtys);
	}

	my $pms = scalar $dbh->selectrow_array(q{
		SELECT count(*) FROM tbl_service_specifications 
		WHERE lngprojectindex = ? AND strname  LIKE  '%pms%name'
	}, undef, $pid);


print STDERR "HAVE DIGIFED: $digifed PMS: $pms ************\n";

	$dbh->do(q{
		UPDATE tbl_projects set digifed = false WHERE lngprojectindex = ?
	},undef,$pid);

	if ( $digifed && !$pms ) {
		$qtys->[0] = $q1;

		my $press_type = 41;

		eprint::print_project::add_qty($r, $log, $dbh, $cookie, $variable, $pid, $qtys, $press_type);
		my ($sfpid, $status) = $dbh->selectrow_array(q{
			SELECT lngprojectindex, strstatus FROM tbl_projects WHERE eid = (
				SELECT eid FROM tbl_projects WHERE lngprojectindex = ?
			) and lngprojectindex <> ?
		},undef, $pid, $pid);

      	my @dprice = project_price($log, $dbh, $pid);
      	my @sprice = project_price($log, $dbh, $sfpid) ;
		if  (  $sprice[0] < $dprice[0] && $status eq 'Unordered'
		) {
			$pid = $sfpid 
		}
		print STDERR "PRICE COMP, $dprice[0], $sprice[0], $pid \n";
	}

	$variable->{pqtys} = $dbh->selectall_arrayref(q{
		SELECT lngprojectindex as id, intQuantity1 as qty FROM tbl_projects
		WHERE eid = ( SELECT eid FROM tbl_projects WHERE lngprojectindex = ? )
	    AND lngprojectindex <> ?
		ORDER BY 1
	},{ Slice => {} }, $pid, $pid); 


####### CUSTOM CODE SECTION ***********


    # Is the user even allowed to view this project?
    return unless project_allowed($dbh, $pid, $variable);

	
	#Only admin/employee can select customer account.
	#Prevent errors when admin makes project and then customer places order.
	if ( $variable->{user_type} =~ /^[AE]$/ ) {

		my ($cust) = $dbh->selectrow_array(q{
				SELECT lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?
		}, undef, $pid);

		eprint::login::select_customer( $r, $log, $dbh, $variable->{cookie}, $variable, $cust );
	}

	#print STDERR "USER DUMPER" , Dumper($variable);
    # Determine if the project is currently in a quote or order and therefor
    # locked from certain actions (site override is possible for staff).
    if (   configuration::get_value($log, $dbh, 'ModifyOrderedProject')
        && $variable->{is_staff} ) 
    {
            $variable->{is_ordered} = 0;
            $variable->{is_quoted}  = 0;
    }
    else {
        $variable->{is_ordered} = $dbh->selectrow_array(q{
            SELECT true FROM tbl_order_contents WHERE lngprojectindex = ?
        }, undef, $pid) ? 1 : 0;

        $variable->{is_quoted} = $dbh->selectrow_array(q{
            SELECT true FROM tbl_quote_details WHERE lngprojectindex = ?
        }, undef, $pid) ? 1 : 0;
    }
    $variable->{is_ordered_or_quoted} = $variable->{is_ordered} 
                                     || $variable->{is_quoted};

    # Render the service pricing section of the project view page.
    $variable->{HeaderInfo} = eprint::docket::header_info($log, $dbh, $pid);
    $variable->{SSRalert}   = configuration::get_value($log,$dbh, 'SuppliedServiceRemovalMessage');

	if ( $r->param('remove_custom_sort') ) {
		$dbh->do(q{ update tbl_project_contents set custom_sort = NUll where lngprojectindex = ? }, undef, $pid);
	}
   
    display_project($log, $dbh, $variable, $pid);

	if ( $r->param('add_custom_sort') )  {
		add_custom_sort($dbh, $pid, $variable); 
    	display_project($log, $dbh, $variable, $pid);
	}

	if ( $r->param('Add Comment') ) { 
		my $comment = $r->param('comment');
		my $assigned_to = $r->param('ddmUser') || $variable->{user_id};
		add_comment($r, $dbh, $variable, $pid, $assigned_to, $comment);
		print STDERR "ADD COMMENT \n\n";
	}

	$variable->{COMMENTS} = $dbh->selectall_arrayref(q{
		SELECT *, date_trunc('Minute', cdate) as fdate,
			(SELECT strfirstname || ' ' || strlastname FROM tbl_customer_users 
			 WHERE lnguserid = c.assignedto ) as assigned_name 
		FROM project_comments c, tbl_customer_users u WHERE pid = ?
		AND c.userid = u.lnguserid 
	}, { Slice => {} } , $pid);

    my $str = q{
          SELECT lngUserID, strFirstName || ' ' || strLastName FROM tbl_Customer_Users 
          WHERE chrtype IN ( 'A', 'E' ) 
          ORDER BY strLastName, strFirstName
	};

    $$variable{'FILL_USER_NAME'} = ssi::fill_drop_down($log, $dbh, $str, '');
	
	$$variable{has_rfq} = $dbh->selectrow_array(q{
		SELECT count(*) FROM rfq WHERE pid = ?
	}, undef, $pid);

	$str = q{
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

	$variable->{quote_id} =  $dbh->selectrow_array(q{
		SELECT max(lngquoteid) FROM tbl_quote_details WHERE lngprojectindex = ?
	}, undef, $pid);

	$variable->{order_id} =  $dbh->selectrow_array(q{
		SELECT max(lngorderid) FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $pid);

	$variable->{product} =  $dbh->selectrow_array(q{
		SELECT prod FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	print STDERR "Comments " , Dumper($variable->{COMMENTS});

	my $sql = "SELECT stremail, strfirstname || ' ' || strlastname  from tbl_customer_users 
					WHERE lngcustomerid = $variable->{cust_id} order by strlastname, strfirstname";

	print STDERR "HAVE USERS: ", Dumper( $sql ); 

    $$variable{'email_to'} = ssi::fill_drop_down($log, $dbh, $sql);

    return OK;
}
sub add_custom_sort {
	my $dbh = shift;
	my $pid = shift;
	my $variable = shift;

	$dbh->do(q{Update tbl_project_contents set custom_sort = 1000 where lngprojectindex = ?}, undef, $pid);


	my $up = $dbh->prepare(q{
		UPDATE tbl_project_contents set custom_sort = ? WHERE lngserviceindex = ?
	});

	my $count = 10000;
	foreach my $c ( @{$variable->{categories}} ) {
			my $list = $c->{services};
			
			map {
				print STDERR "HAVE S: ", Dumper($_->{id});
				$up->execute($count, $_->{id});
				$count += 1000;
			} @{$list};

	}

}

sub add_comment {
	my ($r, $dbh, $var, $pid, $assigned_to, $comment, $email) = @_;
	my $log = $r->log;
	use MIME::QuotedPrint;


	if ( $comment ) { 
		my $ins = $dbh->prepare('INSERT INTO project_comments VALUES ( ?, ?, ?, Now(), ?)');
		$ins->execute($pid, $var->{user_id}, $assigned_to, $comment);
		
		if ( $assigned_to != $var->{user_id} ) {
			my @email = @{$dbh->selectcol_arrayref(q{
				SELECT stremail FROM tbl_customer_users WHERE lnguserid in ( ?, ? )
			}, undef, $assigned_to, $var->{user_id})};

			my $from_name = $dbh->selectrow_array(q{
				SELECT strfirstname || ' ' || strlastname 
				FROM tbl_customer_users WHERE lnguserid = ?
			}, undef, $var->{user_id});

			my $to_name = $dbh->selectrow_array(q{
				SELECT strfirstname || ' ' || strlastname 
				FROM tbl_customer_users WHERE lnguserid = ?
			}, undef, $assigned_to);

		
			my $email_template = misc::load_file($r, '/email/email_template.html');
			my %info;

			$info{'ReplacementText'} = 
				"<!--#include virtual=\"/site_specific/email/content/proj_assign_notification.html\"-->";
			$info{comment} = $comment;
			$info{to_name} = $to_name;
			$info{from_name} = $from_name;
			$info{pid}       = $pid;
			$info{'siteURL'}  = "http://" . $r->hostname;

			$_ = encode_qp(ssi::variable_substitution($r, $log, $dbh, $email_template, \%info));
			my @body = ('', $_, 'text/html', 'quoted-printable');

			my %mail = (
				  SMTP    => configuration::get_value($log, $dbh, 'Mail Server'),
				  FROM    => configuration::get_value($log, $dbh, 'AdministratorEmail'),
				  TO      => join(',',@email),
				  SUBJECT => 'Project Assignment',
			);
print STDERR "EMAIL ", Dumper(%mail);
			misc::send_email_with_attachment($r, $log, \%mail, @body);
		}
	}

} 
# Get the last project the user modified (that they own).
# TODO Get the last modified in the session no matter who owns it. This will
# require a number of changes to how we update the last modified, perhaps not
# worth it.
sub continue_project {
    my ($dbh, $user) = @_;

    return $dbh->selectrow_array(q{
        SELECT lngprojectindex 
        FROM tbl_projects
        WHERE lnguserindex = ?
        ORDER BY dtmlastmodified DESC
        LIMIT 1
    }, undef, $user);
}

sub custom_sort {
	my $dbh   = shift;
	my $pid   = shift;
	my $start = int(shift);
	my $end   = int(shift);

	if ( $start < $end ) {
		$end = $end + 10;
	} else {
		$end = $end - 10;
	}

	$dbh->do(q{ UPDATE tbl_project_contents SET custom_sort = ?  where custom_sort = ? AND lngprojectindex = ?
			}, undef, $end, $start, $pid);


	#Reset all custom ids in the new order.
	my $ids = $dbh->selectall_arrayref(q{
		SELECT lngserviceindex, custom_sort FROM tbl_project_contents WHERE lngprojectindex = ? ORDER by custom_sort
	}, {Slice => {}}, $pid);

	my $up = $dbh->prepare(q{
		UPDATE tbl_project_contents set custom_sort = ? WHERE lngserviceindex = ?
	});

	my $id = 10000;
	map { 
		$up->execute($id, $_->{lngserviceindex});
		$id += 1000;
	} @{$ids};

print STDERR "PIDS: ", Dumper($ids);


}

# Display all the services and pricing for the project.
sub display_project {
    my ($log, $dbh, $variable, $pid) = @_;
    return if !$pid;

    no warnings qw(uninitialized); # We'll be interpolating undef a lot.

    # PROJECT INFO
    #
    $variable->{PressType} = get_press_type($log, $dbh, $pid);
    $variable->{pid}       = $pid;


	my $rfq_only = $dbh->selectrow_array(q{
		SELECT rfq_only FROM tbl_projects WHERE lngprojectindex = ?
	}, undef, $pid);

	my $have_disc = $dbh->selectrow_array(q{
		SELECT COUNT(lngserviceindex) FROM tbl_project_contents 
		WHERE lngprojectindex = ? AND strservicetype = 'Discount'
	}, undef, $pid);

	$rfq_only = 0 if $have_disc;
	$variable->{rfq_only} = $rfq_only;

    my $is_multipage = $variable->{is_multipage} = is_multipage($log, $dbh, $pid);
    my $press_type   = $variable->{press_type}   = get_press_type($log, $dbh, $pid);

    @$variable{qw(ProjectTypeID ProjectTypeName)} = get_type($log, $dbh, $pid);
    
    my $project_type = $variable->{ProjectTypeID};

    my ($project_name, $project_type_url) = $dbh->selectrow_array(qq{
        SELECT strname, strurl FROM tbl_projecttypes WHERE strid = ?
    }, undef, $project_type);

    my $has_locked_services 
        = $variable->{is_fixed_price} = has_locked_services($dbh, $pid);

    my $allowed = $has_locked_services ? allowed_services($dbh, $pid) : undef;

    # PROJECT/SERVICE DISPLAY FLAGS
    #
    # These flags control how prices and edit contols are displayed. To
    # override on a page use: <?eval ($variable->{flag}{name} = value ?>
    my %flags = get_permissions($log, $dbh, $variable, $pid); 
    $variable->{flags} = \%flags;
    $variable->{can_discount}   = can_discount($dbh);
    $variable->{can_item_price} = can_item_price($dbh);

    # DISPLAY STOCK PRICING FOLDED INTO FORMS?
    #
    # If not showing stock pricing broken out we need a signature breakdown
    # for folding it in.
    my $stock_price = {};
    if (!$flags{stock_separate}) {
        $stock_price = eprint::project::sig_stock_prices($log, $dbh, $pid);
    }
    # Otherwise we need the final totals for display.
    else {
        @$variable{qw(stock_price1 stock_price2 stock_price3)} = 
            stock_price($log, $dbh, $pid);
    }

    #loads the change orders
    $variable->{change_order} = PQS::model::change_order::get_change_order($pid);
    $variable->{parent_change_order} = PQS::model::change_order::get_parent_change_order($pid);;


    # HANDLERS
    #
    # Some services need custom handling of their display name, url, or some
    # other aspect. Each handler is called by it's service type string ID and
    # passed a hash representing the pertinent service attributes. Handlers
    # are called as the first operation.
    my %handler_for = (
        # Hide the multi-page "service" as we put the url on the category.
        Book => sub {
            my ($service) = @_;
            $service->{visible} = 0;
            return;
        },

        # Hide the screen item "service" as we put the url on the category.
        Item => sub {
            my ($service) = @_;
            $service->{visible} = 0;
            return;
        },

        # PRINTING
        #
        # Display the project and press type for single sheet projects, and
        # all sorts of signature info for multi.
        Printing => sub {
            my ($print) = @_;

            if ($is_multipage) {
                # Signature information.
                my ($name, $spread_size, $spread_qty, $qty, $run_style, $rows, $cols)
                    = get_specifications($log, $dbh, $pid, $print->{id}, 
                        qw( txtServiceDescription  
                            txtSignatureSize       spreads_in_group
                            txtSignatureQuantity   runstyle
                            hdnImpositionRows      hdnImpositionColumns 
                ));

                # The signature name is a composite of it's description, the
                # number of spreads, and the groups. NOTE: We don't take into
                # account multiple signatures on the same form. TODO: Clean this
                # up.
                $print->{name}  = $name || 'Signature';
                $print->{name}  =~ s/\sSpreads//;

                return if $project_type eq 'ScreenItem';

                # The number of pages.
                my $pages = ($spread_size * $spread_qty);
                my $n_out = ($rows * $cols);

                # Web only has one runstyle, don't bother displaying.
                $print->{name} .= " - $run_style" unless $press_type eq 'web';

                $pages = ($pages > 1) ? "${pages}pg"  : '';
                $qty   = ($qty   > 1) ? "&#215; $qty" : '';
                $n_out = ($n_out > 1) ? "$n_out-out"  : '';
                
                my $desc = '- ' . join(q{ }, (grep { $_ } $pages, $n_out, $qty));
                
                $print->{name} .= " $desc" if length $desc > 2;
            }
            else {
                # Get the string representation of the press. TODO: Really there
                # should be a utility function for this.
                my $sth = $dbh->prepare_cached(q{
                    SELECT strname FROM tbl_equipment_type WHERE strid = ? });
                
                my $press_type_name = $dbh->selectrow_array(
                    $sth, undef, $variable->{PressType});
                
                # The project and press type become our display name.
                $print->{name} = "$variable->{ProjectTypeName} &#8211; $press_type_name";
            }

            return $print;
        },
       

        # SHIPPING
        #
        # Shipping should display what it's shipping in it's name. 
        Shipping => sub {
            my ($s) = @_;
			#my ($name) = get_specifications(
			#    $log, $dbh, $pid, $s->{id}, 'txtServiceDescription');
			#$name =~ s/^\s+(.*?)\s+$/$1/;
			#$s->{name} .= " - $name" if defined $name && $name ne ''; # 0 is OK
			my $p = new PQS::Object::project($pid);
			my $name = $p->delivery_method;
            $s->{name} = "$name" if defined $name && $name ne ''; # 0 is OK
        },
        
        # CUSTOM LINE ITEMS
        #
        # Custom line items should display as their user provided name (if
        # available) not the service type name.
        Custom => sub {
            my ($s) = @_;
            my ($name) = get_specifications(
                $log, $dbh, $pid, $s->{id}, 'ServiceName');
            $name =~ s/^\s+(.*?)\s+$/$1/; # Expensive trim.
            $s->{name} = $name if defined $name and $name ne ''; # 0 is allowed
        },
    );
    
    
    # PROJECT SERVICES
    #
    # Get the full list of project services and their statuses for processing.
    # TODO: Now that we have so many special cases perhaps we want to process
    # these in a dispatch fashion rather than getting the entire list then
    # grepping about.
    my $services = $dbh->prepare_cached(q{
        SELECT c.lngserviceindex AS id,          s.strid       AS ref, 
               s.strname         AS name,        t.strname     AS category1,
               s.strurl          AS url,         c.strstatus   AS status,
               c.lngneedlevel    AS need_level,  c.ysnremoved  AS removed,
               t.lngsort         AS cat_sort,     s.lngindex    AS type,
			   c.custom_sort,	 c.price_override,
               (CASE WHEN s.ysnviewvisible = 'Y' 
                     THEN true 
                     ELSE false
                END)::BOOL       AS visible,

				(CASE WHEN custom_sort > 0
					THEN 'Custom'
					ELSE t.strname
				 END) as category
				
        FROM tbl_project_contents c, 
             tbl_service_types s,
             tbl_service_categories t
        WHERE t.strid = s.strcategory
          AND coalesce(c.strservicetype, 'Printing') = s.strid
          AND c.lngprojectindex = ?
    });
    $services->execute($pid);

    # Project quantities.
    my @qty; @qty[1..3] = get_quantities($log, $dbh, $pid);
    
    # Loop through the services, munge their names, check their prices, create
    # their controls, then add them to their appropriate categories.
    my %category;
    SERVICE:
    while (my $service = $services->fetchrow_hashref) {

        # PREPROCESSING
        #
        # Fire the service off to a pre-processing handler if one exists for
        # it's service type.
        if (my $func = $handler_for{ $service->{ref} }) { 
            &{ $func }($service); 
        }
		
		if ( $service->{custom_sort} ) {
			#$cat = $category{Custom};
			#$service->{category} = 'Custom';

		}

        # SERVICE TYPE CATEGORY
        #
        # Who do we belong to?
        $category{ $service->{category} } = {} 
            unless exists $category{ $service->{category} };
        
        my $cat = $category{ $service->{category} };

        
        $cat->{services} = [] unless exists $cat->{services};

        
        # PRICING
        #
        # Retrieve the pricing for this service.
        my %prices = sql::sql_statement( $log, $dbh, qq|
            SELECT strName, strValue 
            FROM tbl_Service_Specifications 
            WHERE lngProjectIndex = $pid
              AND lngServiceIndex = $service->{id}
              AND ( strName LIKE 'txtPrice%' 
                 OR strName LIKE 'hdnPaperTotal%' 
                 OR strName LIKE 'txtAdditionalPrice%' 
                 OR strName = 'txtSignatureQuantity' )
        |);

        # Prices are stored in text fields in all sorts of formats. Hence all
        # the conditionals to whip them into shape.
        QUANTITY:
        foreach my $i ( 1 .. 3 ) {
            last QUANTITY if $flags{totals_only};
            
            # TODO If the project was ordered we only want to display the ordered
            # quantities pricing.
            # 
            # if ($project->{is_ordered} && this isn't the ordered quantity) {
            #     $service->{"price$i"} = '';
            #     next QUANTITY;
            # }
            
            # If there isn't a quantity for this estimate or the project
            # service was removed from pricing (ie. customer supplied),
            # there's no need for a price.
            if (   $service->{removed} 
                or $qty[$i] <= 0 
                or $prices{"txtPrice$i"} =~ m#n/a#i)
            {
                $service->{"price$i"} = '';
                next QUANTITY;
            } 

            # If the service isn't calculated, just show a placeholder.
            if ( not grep {$service->{status} eq $_} 
                	('calculated', 'In Production', 'Complete', 
				 	 'Pending Deposit', 'Pending Date Approval') ) 
            {
                    $service->{"price$i"} = '-';
                    next QUANTITY;
            }
           
            $service->{"price$i"} = $prices{"txtPrice$i"};
            
            # Add material pricing if we're rolling it in and it has some.
            $service->{"price$i"} += $stock_price->{$service->{id}}[$i-1]
                if ! $flags{stock_seperate} 
                && $service->{ref} eq 'Printing'
                && exists $stock_price->{ $service->{id} };

            # Add the service's price to the category sub total if we're not
            # visible or all per service pricing is turned off for this user.
            if (!$service->{visible} or !$flags{per_service}) {
                $cat->{"sub_total$i"} += $service->{"price$i"};

                $service->{"price$i"} = ''; # Blank the service price display.
            }
			if ( $rfq_only ) {
				$service->{status} = 'RFQ Required';
			}
          }
    

        # INVISIBLE SERVICES
        #
        # We've done all we need to for service we aren't displaying.
        next SERVICE unless $service->{visible};
       
        # USER CONTROLS
        #
        # The user may be able to edit, remove, supply, etc. the service.
        # Products only users aren't allowed however. Nor can dependent
        # services be modified yet.

        my $disabled = grep {$_ == $service->{type}} @{$flags{disabled_services}};

        # Don't display any edit controls for fixed price project services
        # that aren't in the 'allowed' additional services.
        if (  !$variable->{is_staff} 
            && $has_locked_services 
            && !exists $allowed->{ $service->{type} } )
        {
            delete $service->{url};
        }
        elsif ($flags{can_edit} && $service->{status} ne 'dependent' && !$disabled) {
            my @controls;

            my $name = lc $service->{ref};
            push @controls, { 
                name => 'Reset', 
                url  => "/main/proj/dispatch.html?action=edit_line_item;pid=$pid;sid=$service->{id};reset=1;edit_service=1;"
            } if $service->{price_override};


            # Users can edit the service type if it has an edit page.
            push @controls, { 
                name => 'Edit', 
                url  => "/service/$name?pid=$pid;sid=$service->{id}"
            } if $service->{url};

            # If the service isn't already removed (supplied) determine if
            # it can be removed (need level under NEEDED) or supplied.
            if (not $service->{removed} and $service->{ref} ne 'Printing') {
                my $name = $service->{need_level} == NEEDED ? 'Supply' 
                                                            : 'Remove';
                push @controls, { 
                    name => $name,
                    url => "/main/proj/dispatch.html?action=remove;pid=$pid;sid=$service->{id}"
                };
			} else {
                push @controls, { 
                    name => 'Price',
                    url => "/main/proj/dispatch.html?action=remove;pid=$pid;sid=$service->{id}"
                } unless $service->{ref} eq 'Printing';
            }

            # Add Pricing Breakdown linke for employees/admins.
            if ( $variable->{user_type} =~ /^[AE]$/ && $service->{ref} eq 'Printing') {
                push @controls, { 
                    name => '+',
                    url => "/main/proj/proj_printer_summ_price_breakdown.html?ProjectIndex=$pid;ServiceIndex=$service->{id}#chosen"
                };
            }

            $service->{controls} = \@controls;
        }
        # Simple customers don't get any ability to control services.
        else { delete $service->{url}; }
      

		#print STDERR "ADD TO CASTEGORTY: ", Dumper($cat);

        # SERVICE TYPE CATEGORY
        #
        # Add the service to it's category so it will display as a line item.
        push @{ $cat->{services} }, $service;
    }

    
    # FINAL SORT AND CLEANUP
    #
    # Multi-page also need a way to edit their overall information (create
    # stage 3 basically). We're going to promote the category their in to have
    # the editing url. NOTE: Currently hard coded to 'Printing'.
    if ($is_multipage) {
        my $cat = $category{Printing};

        $cat->{id}    = get_print_container($log, $dbh, $pid);
        $cat->{url}   = $project_type eq 'ScreenItem' ? 'item' : 'book' 
            if $flags{can_edit};
    }
    
	# A kludge to get everything in order. If any two services are of the same
	# type we sort them by name. This is primary so signatures are sorted by
	# their newly assigned names. TODO Cache this.
	$variable->{categories} = [
		# Sort categories by preset sort order.
		sort { $a->{services}[0]{cat_sort} <=> $b->{services}[0]{cat_sort} }

		# Sort services by name.
		map { $_->{services} = [
		  sort { $a->{name} cmp $b->{name} } @{$_->{services}}
		]; $_;                                                               }

		# Map the hash to an array of hashes.
		map  { { name => $_, %{$category{$_}} }                              }
			 keys %category
	];


	#Use custom sort order from project_contents table.
	if ( $variable->{categories}[0]{name} eq 'Custom' ) {

		my @a = sort { $a->{custom_sort} <=> $b->{custom_sort} } @{$variable->{categories}[0]{services}} ;

		$variable->{categories}[0]{services} = \@a;
		$variable->{custom_sort} = 1;
	}


	#print STDERR "HAVE SERVICES :", Dumper($variable->{categories});

    # Is there any customer supplied stock in the project?
    ($$variable{'stock_supplied'}) = sql::sql_statement(
        $log, $dbh, qq{
            SELECT MAX(strValue) 
            FROM tbl_Service_Specifications 
            WHERE lngProjectIndex = $pid 
              AND strName = 'stock_supplied'
        }
    );

    $variable->{pid}          = $pid;
    $variable->{qty}          = \@qty;
    $variable->{PaperInfo}    = paper_info($log, $dbh, $pid);
    $variable->{total_price}  = [ undef, project_price($log, $dbh, $pid) ];
      
    # Determine the per unit pricing from the total pricing.
    QUANTITY:
    for my $i (1..3) {
        next QUANTITY unless $qty[$i];

        $variable->{unit_price}[$i] = $variable->{total_price}[$i] / $qty[$i];
    }
       
    @$variable{'CurrencyName', 'CurrencySymbol'} = eprint::customer::get_currency( $log, $dbh, $$variable{'cust_id'} );
    $variable->{is_expired} = eprint::project::validate_project_price($log, $dbh, $pid);

    $variable->{has_pdf_template} = has_pdf_template($log, $dbh, $pid);


    # Check if we're doing a checkout (so we can hide non-applicable stuff).
    $variable->{checkout} = check_for_service($log, $dbh, $pid, 'InventoryCheckOut');

    # If we are a checkout we need to see what the original project was.
    $variable->{checkin_pid} = get_specifications(
        $log, $dbh, $pid, $variable->{checkout}, 'OriginalProjectIndex'
    ) if $variable->{checkout};

#print STDERR "HAVE PROJECT VAR ", Dumper($variable);

    return OK;
}

# Does the current install have the ability to create fixed price products?
# TODO Should we load what services we have as compile time constraints?
sub can_discount   { can_service_type(shift, 'Discount') }
sub can_item_price { can_service_type(shift, 'PerItem')  }

sub can_service_type {
    return shift->selectrow_array(q{
        SELECT true FROM tbl_service_types WHERE strid = ?
    }, undef, shift);
}

# Determine the default customer permission (for viewing pricing).
sub get_permissions {
    my ($log, $dbh, $variable, $pid) = @_;

    my %flags;
	my $ordered = $dbh->selectrow_array(q{
		SELECT lngorderid FROM tbl_order_contents where lngprojectindex = ?
	}, undef, $pid);

    # Get the per customer display flags.
    if ($variable->{user_type} eq 'C') {
        %flags = %{ $dbh->selectrow_hashref(q{
            SELECT ysnpricingprojectview AS totals_only,
                   ysnpricingservices    AS per_service,
                   ysnseparatestock      AS stock_separate,
                   not(ysnproductsonly)  AS can_edit
            FROM tbl_customer
            WHERE lngcustomerid = ?
            }, undef, $variable->{cust_id}
        ) };
    }
    # If we're an admin or employee we have a very permissive default mask.
    else {
        %flags = (
            can_edit       => 1,
            per_service    => 1,
            stock_separate => 1,
            totals_only    => 0,
        );
    }

    # No matter what user type you are, if it's a disabled project you don't
    # get any edit controls.
    $flags{can_edit} = 0 if $dbh->selectrow_array(q{
        SELECT disabled FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

	my $status = project_status($dbh, $pid);
    $flags{can_edit} = 0 if $status eq 'Complete' || $status eq 'Paid';


    # If a project has been ordered lock it down unless the config flag is
    # set to stop this from happening. If the config var is set then just keep
    # the current settings.
    $flags{can_edit} = 0 if ( 
             (   ! configuration::get_value($log, $dbh, 'ModifyOrderedProject')
			  || ! $variable->{is_staff}
			 )
        && $variable->{is_ordered_or_quoted}
    );

    # For Users who are not admins we will now check to see if
    # there are any services that are disabled for this account.

    $flags{disabled_services} = $dbh->selectcol_arrayref(q{
        SELECT service_type FROM customer_service_type
        WHERE customer = ?
    }, undef, $variable->{cust_id}) unless $variable->{is_staff};

    return %flags;
}

# Return a sorted and grouped list of all the stock used in the project.
sub paper_info {
    my ($log, $dbh, $pid) = @_;

    # Get the paper each signature uses.
    my @papers = map signature_paper($log, $dbh, $pid, $_), 
                     check_for_service($log, $dbh, $pid, 'Printing');

    # Collect identical papers (by ID and if they're supplied) so we can
    # display similar papers on the same line. Customer supplied paper is
    # differentiated from printer supplied.
    my %dupe;
    for my $paper (@papers) {
        my $key = "$paper->{id}_$paper->{is_supplied}";
        $dupe{$key} = [] unless exists $dupe{$key};
        push @{ $dupe{$key} }, $paper;
    }

    # Go through and sum the quanties of each paper type.
    for my $papers (values %dupe) {
        for my $n (0..3) {
            $papers->[0]{qty}[$n] = {n => sum map { $_->{qty}[$n] } @$papers};
       		$papers->[0]{"paper_price$n"} = sum map { $_->{"paper_price$n"} } @$papers;
        }
    }

    # Compose the final sorted and grouped list of paper.
    @papers = sort { not ($a->{is_supplied} <=> $b->{is_supplied})
                     || $a->{name} <=> $b->{name}
                     || $a->{width} <=> $b->{width} } 
              map  { $_->[0] } values %dupe;

    return \@papers;
}

# Get the paper information for any given signature.
sub signature_paper {
    my ($log, $dbh, $pid, $sid) = @_;

    # Ensure the signature is priced before we give paper info.
    my $status = get_status($log, $dbh, $sid);
    return wantarray ? () : {} unless grep { $status eq $_ } COMPLETE;

    my %paper = (
        id          => 'hdnPaperIndex',
        name        => 'stock_name',
        colour      => 'stock_colour',
        finish      => 'stock_finish',
        width       => 'hdnSheetSizeWidth',
        height      => 'hdnSheetSizeHeight',
        weight      => 'hdnPaperWeight',
        is_supplied => 'stock_supplied',
        q1          => 'hdnGrossSheetCount1',
        q2          => 'hdnGrossSheetCount2',
        q3          => 'hdnGrossSheetCount3',
        group       => 'txtSignatureQuantity',
        paper_price1       => 'txtStockPrice1',
        paper_price2       => 'txtStockPrice2',
        paper_price3       => 'txtStockPrice3',
    );

    # Because we want to show pounds of paper for web
    # we are going to display the buy quantity b/c it is
    # in pounds instead of the Gross Count which is number of Cutoffs.
     my $press = get_press_type($log, $dbh, $pid);
    if ( $press  eq 'web' ) {
        $paper{q1} = 'hdnPaperBuyQuantity1';
        $paper{q2} = 'hdnPaperBuyQuantity2';
        $paper{q3} = 'hdnPaperBuyQuantity3';
    }
    
    # Check to see if we have a valid project qty before
    # we even look up the stock info.
    my @qtys = $dbh->selectrow_array(q{
        SELECT intquantity1, intquantity2, intquantity3
        FROM tbl_projects WHERE lngprojectindex = ?
    }, undef , $pid );
    for my $i ( 1..3 ) {
        delete $paper{"q$i"} unless $qtys[$i-1];
    }

    # The values in paper are the field names to look up in the database.
    my $fields = join ', ', map { $dbh->quote($_) } values %paper;

    my %values; # We need the hash as 'fields' may be optional.
    $values{$_->[0]} = $_->[1] for @{ $dbh->selectall_arrayref(qq{
        SELECT strname, strvalue 
        FROM tbl_service_specifications
        WHERE lngprojectindex = ? AND lngserviceindex = ?
          AND strname IN ($fields)
    }, undef, $pid, $sid) };

    # Map the values to their new names.
    $paper{$_} = $values{ $paper{$_} } for keys %paper;

    # If we don't know how many are in the group, assume one.
    $paper{group} ||= 1;

    # If the paper is supplied the customer can override the brand and colour.
    if ($paper{is_supplied}) {
        $paper{name}   = $paper{override_brand} ? $paper{override_brand} : '';
        $paper{colour} = $paper{override_brand} if $paper{override_brand};
    }

    # We want the quantities from the yucky way we store them to a nice array.
    $paper{qty} = [];
    my $pattern = qr/^q([1-3])$/o;
    for my $key (grep /$pattern/, keys %paper) {
        my ($i) = $key =~ /$pattern/; $i--;
        $paper{qty}[$i] = $paper{$key} ? int $paper{$key} * $paper{group} : 0;
#This key is still used for display of the paper iformation.
#Do not delete it.
#        delete $paper{"q$i"}
    }

    return \%paper;
}

1;
