package eprint::project;
use strict;
use warnings;
use Data::Dumper;

use base qw(Exporter);

our @EXPORT_OK = qw(
    get_quantities
    get_type
    get_minimum_height
    get_minimum_width
    get_url
    get_press_type
    get_print_container
    get_template
    check_for_service

    get_path
    has_pdf_template

    project_state
    is_complete
    is_predefined
    is_fixed_price
    has_locked_quantity
    has_locked_services
    project_allowed
    allowed_services
    
    get_bindery_type
    has_no_bindery
    is_multipage
    get_signature_indices
	get_cover_sid

    template_service_types

    reset_dependencies

    get_weight
    get_service_index
    get_lf_jobsize
    get_print_presses

    get_finished_calliper

    project_price 
    validate_project_price
    stock_price 
    sig_stock_price
    service_prices

    project_info
    project_status
	mp_versions
	no_print
);
our %EXPORT_TAGS = ( 
    all      => \@EXPORT_OK,
    common   => [ qw( get_quantities       get_type
                      is_multipage         get_press_type
                      get_print_container  get_template
                      check_for_service    get_finished_calliper
                      is_complete          get_path
					  project_status
                      get_minimum_height    get_minimum_width
					  no_print
                )],
    multipage => [ qw( is_multipage          get_bindery_type
                       has_no_bindery        get_signature_indices
                       get_finished_calliper get_cover_sid
                )],
    pricing => [ qw( project_price  validate_project_price
                     stock_price    sig_stock_price
                     service_prices
              )],
    state => [ qw( project_state    is_complete          is_predefined
                   is_fixed_price   has_locked_quantity  has_locked_services
                   project_allowed  allowed_services) ],
);

use List::Util qw(sum);

require eprint::service;

# The following set of utility functions are a first attempt at abstracting
# some of most queried database states from the code. They're a pain to write
# but better than what we have now and an okay intermediate step to a better
# encapsulation system whatever we decide that to be.


# Returns the path to project files.
sub get_path {
    my ($log, $dbh, $pid) = @_;

    # Get the path to the customers files.
    my $cid = $dbh->selectrow_array(q{
        SELECT lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

    my $customer = eprint::obj_customer->new($log, $dbh, $cid);

    my $path = Apache2::RequestRec->dir_config('site_specific')
            || Apache2::RequestRec->document_root.'/site_specific/';
    
    return "$path/customers/" . $customer->path . "/projects/$pid/";
}


sub no_print {

	my $pid = shift;
	my $dbh = session::dbh;
	my $log = session::log;
	return get_type($log, $dbh, $pid) eq 'NoPrint';
}

# Does the project have a PDF template?
sub has_pdf_template {
    my ($log, $dbh, $pid) = @_;

    my $path = get_path(@_);

    return -e "$path/.template/template.pdf";
}

sub mp_versions {
	my $pid = shift;
	my $dbh = session::dbh();
	my $log = session::log();

	my $bookid = eprint::project::get_service_index($log, $dbh, $pid, 'Book');

	return 1 unless $bookid;


	my %vspecs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $bookid);

	my @versions = eprint::Service::Book::mp_versions(\%vspecs);


	my $num_versions = 0;

	map {
		$num_versions++ if $_->{name}{value} && $_->{qty}{value};
	} @versions;

	$num_versions = $num_versions > 1 ? $num_versions : 1;

	return $num_versions;
}


# Check that the project exists and the current customer is allowed to use it.
sub project_allowed {
    my ($dbh, $pid, $variable) = @_;

    my $id = $dbh->selectrow_array(q{
        SELECT lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

    return unless $id; # Project doesn't exist.

    # The user is allowed if they're the owner or an employee/admin.
    return ($variable->{user_type} =~ /^[AE]$/ || $id == $variable->{cust_id});
}


# Get the current project state.
sub project_state {
    my ($dbh, $pid) = @_;


    return $dbh->selectrow_array(q{
        SELECT strstatus
        FROM tbl_projects
        WHERE lngprojectindex = ?
    }, undef, $pid);
}

# Returns the string project service status given the ID of one.
sub project_status {
    my ($dbh, $pid, $status) = @_;

	if ( $status ) {
		$dbh->do(q{UPDATE tbl_projects set strstatus = ? WHERE lngprojectindex = ?}, undef, $status, $pid);
	}

    my $sth = $dbh->prepare_cached(q{
        SELECT strstatus 
        FROM tbl_projects
        WHERE lngprojectindex = ?
    });
    return $dbh->selectrow_array($sth, undef, $pid);
}

sub is_predefined { return project_state(@_) eq 'predefined' }

# Return true if the project is "finished" (one of a number of states).
sub is_complete {
    my ($log, $dbh, $pid) = @_;

   return $dbh->selectrow_array(qq{
        SELECT count(*) = 0
        FROM tbl_Project_Contents
        WHERE lngProjectIndex = ?
          AND strStatus NOT IN ( 'calculated',    'Complete', 
                                 'In Production', 'Pending Deposit', 'Pending Date Approval', 'Waiting For Files' )
    }, undef, $pid);
}

# Returns true if the project has any of the price setting services on it.
sub is_fixed_price { has_locked_services(@_) }

# Some fixed price projects have set quantities that can't be changed.
sub has_locked_quantity {
    my ($dbh, $pid) = @_;
   
    return check_for_service(undef, $dbh, $pid, 'Discount');
}

# Fixed price or fixed item price projects include certain services in the
# price, these services can't be editted by the user (for obvious reasons).
sub has_locked_services {
    my ($dbh, $pid) = @_;
    
    return;
    return check_for_service(undef, $dbh, $pid, 'Discount')
        || check_for_service(undef, $dbh, $pid, 'PerItem');
}


# If the project is a fixed price, only certain services are allowed to be
# added to it.
sub allowed_services {
    my ($dbh, $pid) = @_;
    my @services;


    # If we're a fixed price project use the service list from there.
    if (my $sid = is_fixed_price($dbh, $pid)) {

        my $service_type = eprint::service::load_service_type(
            $dbh->selectrow_hashref(q{
                SELECT t.strid AS type, t.strmodule AS module
                FROM tbl_service_types t, tbl_project_contents c
                WHERE c.strservicetype = t.strid
                  AND c.lngserviceindex = ?
            }, undef, $sid)
        );
        
        my $specs = eprint::service::get_specs($dbh, $pid, $sid, $service_type);

        # No restrictions so all are allowed.
        return undef unless exists $specs->{services}
                         && ref $specs->{services} eq 'ARRAY';


        @services = @{ $specs->{services} };
    }
    # Otherwise we use the standard
    else {
    	# Only predefined projects could have restricted services.
    	return undef unless is_predefined($dbh, $pid);
   
        my $list = configuration::get_value(
            undef, $dbh, 'predefined_allowed_services'
        );

        return undef unless $list; # No default so all are allowed.

        @services = split /,/, $list;
    }

    # Return an existance hashref for easy checking.
    if (!wantarray) {
        my %exist;
        @exist{ @services } = (1) x @services;
        return \%exist;
    }
    else { return @services }; # Or the list.
}


# Return the given project's estimate quantities.
sub get_quantities {
    my ($log, $dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT intQuantity1, intQuantity2, intQuantity3
        FROM tbl_Projects
        WHERE lngProjectIndex = ?
    });
    return $dbh->selectrow_array($sth, undef, $pid);
}

# Given a project id and a service type name it
# will return the service index.
sub get_service_index {
    my ($log, $dbh, $pid, $service) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT lngserviceindex
        FROM tbl_project_contents
        WHERE lngprojectindex = ?
          AND strservicetype  = ?
      });
        return scalar $dbh->selectrow_array($sth, undef, $pid, $service);
}

# Returns the give projects 'Print' service.
sub get_print_container {
    my ($log, $dbh, $pid) = @_;

    my @sid = check_for_service($log, $dbh, $pid, 'Book')
           || check_for_service($log, $dbh, $pid, 'Item')
           || check_for_service($log, $dbh, $pid, 'InventoryCheckOut')
           || check_for_service($log, $dbh, $pid, 'Printing');

    return $sid[0];
}

# Returns a boolean flag indicating if the current project is multipage.
sub is_multipage {
    my ($log, $dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT ysnmultipage
        FROM tbl_projecttypes t, tbl_projects p 
        WHERE p.lngprojecttype  = t.lngindex 
          AND p.lngprojectindex = ?
    });
    return $dbh->selectrow_array($sth, undef, $pid);
}

# Return the given project's type.
sub get_type {
    my ($log, $dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT t.strid, t.strname
        FROM tbl_projecttypes t, tbl_projects p 
        WHERE p.lngprojecttype  = t.lngindex 
          AND p.lngprojectindex = ?
    });
    my @info = $dbh->selectrow_array($sth, undef, $pid);

    return wantarray ? @info : $info[0];
}

#get the minimum width allowed for a project
sub get_minimum_width {
    my ($log, $dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT t.minwidth
        FROM tbl_projecttypes t, tbl_projects p
        WHERE p.lngprojecttype  = t.lngindex
          AND p.lngprojectindex = ?
    });
    my @info = $dbh->selectrow_array($sth, undef, $pid);

    return wantarray ? @info : $info[0];
}

#get the minimum height allowed for a project
sub get_minimum_height {
    my ($log, $dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT t.minheight
        FROM tbl_projecttypes t, tbl_projects p
        WHERE p.lngprojecttype  = t.lngindex
          AND p.lngprojectindex = ?
    });
    my @info = $dbh->selectrow_array($sth, undef, $pid);

    return wantarray ? @info : $info[0];
}

# Return the project type url for the given project
sub get_url {
    my ($dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT t.strurl 
        FROM tbl_projecttypes t, tbl_projects p
        WHERE p.lngprojecttype  = t.lngindex
          AND p.lngprojectindex = ?
    });
    return $dbh->selectrow_array($sth, undef, $pid);
}


# Returns the project's press type. This is an interim measure until such time
# as we can price for any set of press types.
sub get_press_type {
    my ($log, $dbh, $pid, $sid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT t.strid 
        FROM tbl_equipment_type t, tbl_projects p 
        WHERE p.lngpresstype  = t.lngindex 
          AND p.lngprojectindex = ?
    });
    my $type =  $dbh->selectrow_array($sth, undef, $pid);

	if ( $type eq 'web' && $sid ) {
		my $cover_type = $dbh->selectrow_array(q{
			SELECT strvalue FROM tbl_service_specifications
			WHERE lngserviceindex = ? and strname = 'txtSignatureType'
		},undef,$sid);

		if ($cover_type eq 'Cover Spreads') {
			my $config = configuration::get_value($log, $dbh,'WebCoverPressType');
			$type = $config if $config;
		}
	}

    return $type
}

sub get_cover_sid {
	my ($dbh, $pid) = @_;
	return $dbh->selectrow_array(q{
		SELECT lngserviceindex FROM tbl_service_specifications
		WHERE strname = 'txtSignatureType' 
		      	and strvalue = 'Cover Spreads' 
				and lngprojectindex = ?
	}, undef, $pid);
}

sub get_print_presses {
    my ($log, $dbh, $pid) = @_;

    my @presses;
    foreach my $sid (get_signature_indices($log, $dbh, $pid)) {
        push @presses, $dbh->selectrow_array(q{
                SELECT strvalue
                FROM tbl_service_specifications
                WHERE strname = 'press'
                  AND lngserviceindex = ?
             }, undef, $sid);
    }
    return \@presses;
}

# Return the chosen project template.
sub get_template {
    my ($log, $dbh, $pid) = @_;

    return $dbh->selectrow_array(q{
        SELECT strvalue
        FROM tbl_service_specifications
        WHERE strname = 'template'
          AND lngserviceindex = ?
    }, undef, get_print_container($log, $dbh, $pid));
}

# Returns the bindery type or undef if the project is single-page or bindery
# hasn't been defined.
sub get_bindery_type {
    my ($log, $dbh, $pid) = @_;

    return undef unless is_multipage($log, $dbh, $pid);
    
    my $sth = $dbh->prepare_cached(q{
        SELECT strvalue
        FROM tbl_service_specifications
        WHERE strname = 'template'
        AND lngprojectindex = ?
        AND lngserviceindex = ?
    });
    my $bindery = $dbh->selectrow_array(
        $sth, undef, $pid, get_print_container($log, $dbh, $pid));

    return $bindery if defined $bindery and $bindery ne '';
    return undef;
}


# Return falseif the project has bindery, doesn't have bindery, or the status of
# bindery is unknown (undef).
sub has_no_bindery {
    my ($log, $dbh, $pid) = @_;

    return $dbh->selectrow_array(q{
        SELECT strvalue
        FROM tbl_service_specifications
        WHERE strname = 'no_bindery'
        AND lngprojectindex = ?
        AND lngserviceindex = ?
	}, undef, $pid, get_print_container($log, $dbh, $pid));
	
}


# Return the weight of an individual project (an optional fourth attribute can
# be set to 'Proofs' to give just the proof weight).
sub get_weight {
    my ($log, $dbh, $pid, $type) = @_;
    
    # Default the weight to project until a refactor.
    $type = 'Project' unless defined $type;

    my $func = $type eq 'Proofs'  ? \&get_proof_weight
             : $type eq 'Project' ? \&get_signature_weight
             : $type eq 'Other'   ? \&get_signature_weight
			 : $type  eq 'Product' ? \&get_product_weight
             :                       undef;

    die "Uknown weight type ($type)." unless $func;
        
    # For the non-book case, this devolves into the printing service
    my $weight = 0;
    foreach my $sid (check_for_service($log, $dbh, $pid, 'Printing')) {
        $weight += $func->($log, $dbh, $pid, $sid);
    }

    return $weight;
}

sub get_product_weight {
    my ($log, $dbh, $pid, $sid) = @_;
	return 1;
}

# Get the weight of an individual signature.
sub get_signature_weight {
    my ($log, $dbh, $pid, $sid) = @_;


    my $ptype = get_type($log, $dbh, $pid);

	return 1 if $ptype eq 'NoPrint';

    #For Screen items the weight is in the print container.
    if ( $ptype eq 'ScreenItem' ) {
        return eprint::service::get_specifications(
            $log, $dbh, $pid, check_for_service($log, $dbh, $pid, 'Item'),
            'txtScreenPrintingItemWeight'
        );
    }
        

    my ($mweight,    $sheet_width,  $sheet_height,  $width,      $height, 
        $imposition, $spread_width, $spread_height, $spread_qty, $pad_pages,
		$forms_in_group                                                    ) = 
            eprint::service::get_specifications($log, $dbh, $pid, $sid, qw(
                txtMWeight       hdnSheetSizeWidth  hdnSheetSizeHeight  
                flat_width       flat_height        txtImposition
                txtSpreadWidth   txtSpreadHeight    spreads_in_group
                pad_sheets		 txtSignatureQuantity
    ));

  #die "Invalid MWeight ($mweight) for project ($pid) signature ($sid)."
  #unless $mweight && int $mweight > 0;

    $spread_width  ||= $width;
    $spread_height ||= $height;

    # if this is a brochure then the project_weight should be the weight of 1 brochure.
    $spread_qty ||= 1;

    $spread_qty *= $forms_in_group if $forms_in_group && $forms_in_group > 1;
    $spread_qty = $pad_pages       if $pad_pages      && $pad_pages > 1;
    
    #$spread_qty = $imposition if ! $spread_qty;
    
    # Note that the mweight of 15 point board stock is 190 - we'll
    # assume this weight for inkjet stock for now this is a bad kludge
    # that we will use until such a time as we do inkjet properly.
    # We'll also assign anything to this that fails to have an mweight
    # at all, since some heavy weight is better than 0lbs.
    $sheet_width  ||= $width;  # Added to make weight failures work
    $sheet_height ||= $height; # Added to make weight failures work

    my $sheet_size = $sheet_width * $sheet_height;

    $mweight = 190 if ! $mweight; # New line to make weight failures work
    $mweight /= 1000;

    my $weight = ($ptype eq 'Envelopes')
        ? $mweight
        : $spread_qty * ($mweight / ($sheet_size)) * ($spread_width * $spread_height);

    return $weight;
}

# Get the weight of the proofs for an individual signature.
sub get_proof_weight {
    my ($log, $dbh, $pid, $sid) = @_;

    my $weight = 0;

    my $proof = scalar $dbh->selectrow_array(q{
        SELECT lngserviceindex
        FROM tbl_project_contents
        WHERE lngprojectindex = ?
          AND strservicetype = 'Proofs'
    }, undef, $pid);

    my $sig = eprint::service::get_specifications($log, $dbh, undef, $sid, 'SignatureIndex');

    my $i    = 1;
    my $flag = 1;
    while ($flag) {
        my ($width, $height, $qty) = 
            eprint::service::get_specifications($log, $dbh, $pid, $proof, 
                "txtProofWidth-$sig-$i",
                "txtProofHeight-$sig-$i",
                "txtProofQuantity-$sig-$i",
            );

        if ($qty) {
            $weight += $qty * ($width * $height) * 0.0003982142;
            # The number comes from mweight = 446 / ((28 * 40) *1000)
            $i++;
        } 
        else {
            $flag = 0;
        }
    }

    return $weight;
}


# Get the id(s) of services of the given type in the project (in create order).
sub check_for_service {
    my ($log, $dbh, $pid, $service_type) = @_;
    my $sid;

    my $sth = $dbh->prepare_cached(q{
        SELECT lngserviceindex 
        FROM tbl_project_contents
        WHERE lngprojectindex = ?
          AND strservicetype = ?
        ORDER BY lngserviceindex
    });
    $sth->execute($pid, $service_type);
    $sth->bind_col(1, \$sid);

    if (! wantarray) {
        $sth->fetch;
        $sth->finish;
        return $sid;
    }
    else {
        my @sids;
        push @sids, $sid while $sth->fetch;
        return @sids;
    }
}

# Returns the service IDs of all signatures/flat printing service.
sub get_signature_indices { check_for_service(@_, 'Printing') } 


# Tries to determine the final depth of the project, be it flat sheet, folded
# sheet, or bound book.
sub get_finished_calliper { 
    my ( $log, $dbh, $variable, $pid, $folding, $project_type ) = @_; 

    $folding = check_for_service($log, $dbh, $pid, 'Folding') if ! $folding;

    my $printing_service_index = get_print_container($log, $dbh, $pid);
    
    my $sheet_calliper = $variable->{txtStockCalliper};
    if ( ! $sheet_calliper ) {
        ( $sheet_calliper ) = eprint::service::get_specifications( 
            $log, $dbh, undef, $printing_service_index, 'txtStockCalliper' 
        );
    }

    $project_type = get_type($log, $dbh, $pid) unless $project_type;

    my @signatures = check_for_service($log, $dbh, $pid, 'Printing');

    if ( is_multipage($log, $dbh, $pid) && @signatures ) {
        my $book_calliper = 0;

        foreach my $index ( @signatures ) {
            my ( $calliper, $spreads, $imposition, $signatures, $sig_size )
                = eprint::service::get_specifications(
                    $log, $dbh, undef, $index,
                    qw(txtStockCalliper spreads_in_group hdnImposition
                       txtSignatureQuantity txtSignatureSize          )
                );

            # 4 page spreads are folded in half so calliper is doubled.
            # 2 Page spreads are not folded in half. ( Perfect Binding, Coil Binding )
            $book_calliper += $calliper 
                            * $spreads 
                            * ($signatures || 1) 
                            * ($sig_size == 2 ? 1 : 2);

            $variable->{txtSignatureCount} += $signatures || 1;
        }

        return $book_calliper;
    }
    elsif ( $project_type =~ /Pad/ ) {
        my $print = get_print_container($log, $dbh, $pid);
        my $pages = eprint::service::get_specifications($log, $dbh, undef, $print, 'pad_sheets') || 1;

        return $pages * $sheet_calliper;
    }
    elsif ( $project_type eq 'PressSheetCombination' ) {
        return $variable->{txtStockCalliper};
    }
    elsif ( $folding ) {
        my %spec = @{ $dbh->selectcol_arrayref(q{
            SELECT strName, strValue 
            FROM tbl_Service_Specifications 
            WHERE lngServiceIndex = ?
              AND strName like 'txt%'
          }, { Columns => [1,2] }, $folding) };

        no warnings qw(uninitialized);

        my ($fold) = grep { /^txt(.*?)FoldQty$/ } keys %spec;

        my $pages = $fold =~ /(\d)Panel/     ? $1
                  : $fold =~ /(\d)Signature/ ? int($1/2)
                  : $fold eq 'SingleGate'     ? 3
                  : $fold eq 'DoubleGate'     ? 4
                  : $fold eq 'Difficult'      ? 6
                  :                             1;

        return $pages * $sheet_calliper;
    }

    return $sheet_calliper;
}

sub get_lf_jobsize {
    my ($imp) = @_;

    my ($paper_width, $paper_height) = @{$imp->getPaper}{qw( width height )};

    return $imp->getPaper->{type} eq 'roll'
         ? $paper_width * $imp->getCutOff * $imp->getSpreads
         : $paper_width * $paper_height   * $imp->getSpreads;
}


# Project templates contain needed service types and specifications for those
# service types. Given a project id, return a hash of service types needed
# each containing a hash of specifications.
sub template_service_types {
    my ($log, $dbh, $pid) = @_;
    
    my $project_type = get_type($log, $dbh, $pid);
    my $template     = get_template($log, $dbh, $pid);
    
    # Template specifications without project types apply to all project
    # types, even if the project type is present. In the case of a name
    # collision the more specific one (one with a project type) is chosen.
    #    
    # Ensure NULL project type specs come before ones with a type, so that
    # they'll be overwritten.
    my $sth = $dbh->prepare(q{
        SELECT strservice, strname, strvalue, ysnrequired
        FROM tbl_template_specifications
        WHERE strprojecttype = ? OR strtemplatetype = ?
        ORDER BY strservice, strname, 
                 (strprojecttype IS NULL), (strtemplatetype IS NULL)
    });
    $sth->execute($project_type, $template);
    my ($service, $key, $value, $require_level);
    $sth->bind_columns(\$service, \$key, \$value, \$require_level);

    my %service_type;
    while ($_ = $sth->fetch) {
        # Seeing as template specifications is such a hack of a table
        # the requirement is defined on each spec. when it should be defined
        # on the service itself. So we choose the highest requirement level on
        # any specs. for the service type and adjust the boolean return to an
        # integer need level.
        $service_type{$service}{required} = 1 + $require_level
            if ! exists $service_type{$service}{required}
            || $service_type{$service}{required} < 1 + $require_level;

        next unless defined $key && $key ne '';

        # Create a hash of specifications for each service type.
        $service_type{$service}{specs}{$key} = $value;
    }
    
    return wantarray ? %service_type : \%service_type;
}



use constant START_DEP => 0;

# Reset all project service dependencies in the current project.
sub reset_dependencies {
    my ($log, $dbh, $pid) = @_;
    
    # Project services and their type's dependency level.
    my $services = $dbh->selectall_arrayref(q{
        SELECT id, type, level
        FROM project_service_status
        WHERE project = ?
    }, { Slice => {} }, $pid);

    my (@dep, @calc);
    for my $s ( @$services ) {
        # Anything that depends on a signature becomes 'dependent'.
        if ($s->{level} > START_DEP)        { push @dep,  $s }
        
        # Everything else (other than custom line items), including those
        # outside of our dependecy system, should become 'uncalculated'.           
        elsif ( $s->{type} ne 'Custom' ) { push @calc, $s }
    }
   
    # Set dependent statuses.
    set_status($log, $dbh, $pid, 'dependent', (map { $_->{id} } @dep))
        if @dep;

    # For uncalculated there is one exception, if we're multipage the
    # 'Print' container doesn't define pricing so should stay as it is.
    @calc = grep {$_->{type} ne 'Printing'} @calc 
        if is_multipage($log, $dbh, $pid);
    set_status($log, $dbh, $pid, 'uncalculated', (map { $_->{id} } @calc))
        if @calc;

    # NOTE: Javascript only services that get reset will force the user to
    # go through them (to the page) again to calculate.
   
    return 1;
}

# Get the stock totals (per estimate qty) per signature for the given project.
sub sig_stock_prices {
    my ($log, $dbh, $pid) = @_;
    my (%stock, $sid, $key, $price); 
    
    # Lookup any stock prices stored with printing/signatures.
    my $sth = $dbh->prepare_cached(q{
        SELECT s.lngserviceindex, s.strname, s.strvalue::NUMERIC
        FROM tbl_service_specifications s, tbl_project_contents c
        WHERE s.lngserviceindex = c.lngserviceindex
          AND s.lngprojectindex = c.lngprojectindex
          AND c.strservicetype = 'Printing'
		  AND c.strstatus NOT IN ('uncalculated', 'Deleted')
          AND s.strvalue NOT IN ('N/A', 'n/a', '')
          AND c.ysnremoved = FALSE
          AND s.strname ~ '^txtStockPrice[1-3]$'
          AND s.lngprojectindex = ?
    });
    $sth->execute($pid);
    $sth->bind_columns(\$sid, \$key, \$price);

    # A list of stock prices (one per estimate qty) for each signature.
    while ($sth->fetch) {
        $stock{$sid} = [0, 0, 0] unless exists $stock{$sid};
        $key =~ /([1-3])$/;
        next unless defined $1;
        
        # Our policy now is remove decimals from all stock and service total.
         $stock{$sid}[$1 - 1] = $price;
#        $stock{$sid}[$1 - 1] = int($price);
    }

    return \%stock;
}

# Totals service and material (currently only stock) prices for the project.
sub project_price {
  my ($log, $dbh, $pid) = @_;

  my @total;
  my @material = stock_price($log, $dbh, $pid);
  my @service  = map { $_ ? sum( map { $_->{price} } values %$_ ) : 0 } @{ service_prices($dbh, $pid) };

  $total[$_] = ($service[$_] // 0) + ($material[$_]//0) for 0..(scalar @service); 

  print STDERR "HAVE PROJECT PRICES: ", Dumper(\@material, \@service, \@total);

  return @total;
}

# Returns a hash of the service type and price of each service in the project.
sub service_prices {
    my ($dbh, $pid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT c.lngserviceindex                AS sid,
               t.lngindex                       AS type,
               c.strservicetype                 AS service, 
               coalesce(s.strvalue::NUMERIC, 0) AS price
        FROM tbl_service_specifications s, 
             tbl_project_contents c,
             tbl_service_types t
        WHERE c.lngprojectindex = s.lngprojectindex
          AND c.lngserviceindex = s.lngserviceindex
          AND c.strservicetype  = t.strid
		  AND c.strstatus NOT IN ('uncalculated', 'Deleted')
          AND s.strvalue NOT IN ('N/A', 'n/a', '')
          AND c.ysnremoved = false
          AND s.strname   = 'txtPrice' || ?::char(1)
          AND c.lngprojectindex = ?
    });

    my @qty = (undef, get_quantities(undef, $dbh, $pid));

    # Ensure a three element array(where Q2 could be missing).
    my @prices;
    for my $i (1..3) {
        unless ($qty[$i] && $qty[$i] > 0) {
            push @prices, undef;
            next;
        };
        
        push @prices, $dbh->selectall_hashref($sth, 'sid', {}, $i, $pid);
    }

    return \@prices;
}

# Sum all per signature stock totals.
sub stock_price {
    my $stock = sig_stock_prices(@_);

    no warnings qw(uninitialized);

    my @totals;
    for my $n (0..2) {
        push @totals, sprintf '%.2f', sum( map { $_->[$n] } values %$stock );
    }

    return @totals;
}

sub validate_project_price {
    my ($log, $dbh, $pid) = @_;

    my $days = $dbh->selectrow_array(q{
        SELECT to_char( (dtmexpiredate - NOW()), 'dd' )
        FROM tbl_projects
        WHERE lngprojectindex = ?
    }, undef, $pid);

    return $days < 1; # Returns true if expired
}

# Gives bacic project info; quantities, project type, and press type.
sub project_info {
    my ($dbh, $pid) = @_;

    my %project = ( id => $pid );

    # Get project quantities.
    $project{quantity} = $project{qty} = [ get_quantities(undef, $dbh, $pid) ];

    # Get the project type's id, reference, name, etc.
    $project{type} = $dbh->selectrow_hashref(q{
        SELECT t.lngindex     AS id,
               t.strid        AS ref,
               t.strname      AS name,
               t.ysnmultipage AS is_multipage
        FROM tbl_projects p, tbl_projecttypes t
        WHERE p.lngprojecttype = t.lngindex
          AND p.lngprojectindex = ?
    }, undef, $pid);
    $project{is_multipage} = $project{type}{is_multipage};
    
    # Same for the press type.
    $project{press_type} = $dbh->selectrow_hashref(q{
        SELECT t.lngindex     AS id,
               t.strid        AS ref,
               t.strname      AS name
        FROM tbl_projects p, tbl_equipment_type t
        WHERE p.lngpresstype = t.lngindex
          AND p.lngprojectindex = ?
    }, undef, $pid);

    return \%project;
}

1;
