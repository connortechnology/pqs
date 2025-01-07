package eprint::print_project;
use strict;
use warnings;
no warnings qw(uninitialized); # TODO only for display functions

use base qw(Exporter);
our @EXPORT_OK = qw( 
    insert_service  remove_service  delete_service copy_project
);

our %EXPORT_TAGS = ( common => \@EXPORT_OK );

use Apache2::Const  qw(:common HTTP_MOVED_TEMPORARILY);
use JSON::XS 2.0       qw(encode_json);
use List::Util         qw(sum reduce first);
use Compress::LZF      qw(:freeze);
use Mail::Sendmail;
use MIME::Base64;
use MIME::QuotedPrint;
use POSIX              qw(ceil);

use ssi                      ();
use sql                      qw(:common);
use configuration            ();
use eprint::service          qw(:all);
use eprint::project          qw(:common :state reset_dependencies has_pdf_template);
use PQS::Imposition::Colour  qw(:all);
use PQS::model::change_order;
use PQS::model::order;

use Data::Dumper;

require misc;
require eprint::login;
require eprint::obj_customer;
require eprint::inventory;
require eprint::user;
require eprint::Build;


# Given a project ID and a string project type, insert the name and all
# project type default service specifications into the 'Print' container
# service. This is used during the initial project create phase.
sub insert_project_type {
    my ($r, $log, $dbh, $pid, $project_type_id) = @_;

    my $project_type_index = $dbh->selectrow_array(q{
        SELECT lngindex FROM tbl_projecttypes WHERE strid = ?
    }, undef, $project_type_id);

    # Some basic guard clauses. Really we should die here or -- better yet --
    # just insert default specs. Anything other than what we do.
    die "Couldn't find project type: $project_type_id"
        if ! defined $project_type_index || ! $project_type_index;

    # We have three starting blocks for projects.
    my $type = $project_type_id eq 'ScreenItem' ? 'Item'      # Screen items
             : is_multipage($log, $dbh, $pid)   ? 'Book'      # Multipage
             :                                    'Printing'; # Flat/folded

    # Create the initial service. 
    my $sid = insert_service($log, $dbh, $pid, $type, {
            need_level     => NEEDED,
            user_requested => 1,  # Should we set to yes?
    });

    # Insert the default specification for all projects and the specific
    # project type into the 'Print' service's specifications.. 
    my $defaults = project_type_defaults($dbh, $project_type_index);

    # While we'd really rather do this all within the database this will work
    # for now.
    insert_service_specs($log, $dbh, $pid, $sid, %$defaults);

    return 1;
}

sub project_type_defaults {
    my ($dbh, $project_type) = @_;

    # In the case of identical specs, ensure the least specific (NULL project
    # type) specs come before the most specific so the least will be
    # overwritten.
    my %defaults = @{ $dbh->selectcol_arrayref(q{
        SELECT strfieldname, strdefaultvalue 
        FROM tbl_projecttype_defaults
        WHERE ( lngprojecttypeindex IS NULL
             OR lngprojecttypeindex = ? )
         ORDER BY (lngprojecttypeindex IS NOT NULL), strfieldname
    }, { Columns => [1,2] }, $project_type) };

    return \%defaults;
}

sub insert_service {
    my ($log,
        $dbh,
        $pid,          # Project ID.
        $service_type, # Service type string ID.
        $attr,         # Optional attributes hashref.
        $specs,        # Service specifications hashref.
    ) = @_;

	$dbh->do(q{update tbl_projects set build = true where lngprojectindex = ?}, undef, $pid);
    
    # Get the numeric ID from the string one.
    my $stid = $dbh->selectrow_array(q{
        SELECT lngindex FROM tbl_service_types WHERE strid = ?
    }, undef, $service_type);

    # If the service type isn't found log an error and don't insert.
    unless ($stid) {
        $log->error("Couldn't get service index for $service_type.");
        return;
    }
   
    # Check the dependency level of the service being inserted against the
    # lowest uncalculated service.
    my $dependent = $dbh->selectrow_array(q{
        SELECT ( SELECT MIN(level) 
                 FROM project_service_status
                 WHERE status  = 'uncalculated'
                   AND project =  ? ) < lngdep
        FROM tbl_service_types
        WHERE strid = ?
    }, undef, $pid, $service_type);

    my $status = $dependent ? 'dependent' : 'uncalculated';
    
    # Due to our lovely table naming let's map our nice names to the
    # fields after we filter out uknown arguements.
    my %args;
    my %arg_map = (
        user_requested => 'ysnuserrequested',
        need_level     => 'lngneedlevel',
        status         => 'strstatus',
    );
    for my $n (keys %arg_map) {
        next unless exists $attr->{$n};
        $args{ $arg_map{$n} } = $attr->{$n}
    }
    
    # Insert the project service.        
    insert(
        $log, $dbh, 'tbl_project_contents', %args,
        lngProjectIndex => $pid,
        strStatus       => $status,
        strservicetype  => $service_type,
    );
    # Get the current contents service id. Should use
    # $dbh->last_insert_id() when it's available.
    my $sid = $dbh->selectrow_array(
        q{ SELECT currval('ContentsServiceIndex_seq') }
    );

    # Adjust any project services that may now be dependent on us.
    recalc_dependencies($log, $dbh, $pid, $sid);

    # Copy the defaults for the current service type to the service
    # specification being created.
    $dbh->do(qq{
        INSERT INTO tbl_service_specifications
            (lngprojectindex, lngserviceindex, strname, strvalue)
            ( SELECT $pid, $sid, strfieldname, strdefaultvalue 
              FROM tbl_service_defaults
              WHERE lngserviceindex = ( SELECT lngindex
                                        FROM tbl_service_types
                                        WHERE strid = ? ))
    }, undef, $service_type);

    # Insert the any specifications that were given.
    if (keys %$specs) {
        while (my ($field, $value) = each %$specs) {
            insert_service_spec($log, $dbh, $pid, $sid, $field, $value);
        }
    }

    return $sid;
}



# Returns a hashref of categories that contain an array of project type hashes
# for easy use with SSI.
sub project_types {
    my ($log, $dbh) = @_;
    
    # Get the customer's project types. TODO: Setup categories in the project
    # types so we don't have to do weird dispatch stuff?
    my $project_type = $dbh->prepare_cached(q{
        SELECT lngindex, strid, strname, ysnmultipage
        FROM tbl_projecttypes
        ORDER BY lngsort;
    });
    $project_type->execute;

    my ($id, $ref, $name, $multi); 
    $project_type->bind_columns(\$id, \$ref, \$name, \$multi);
    
    my %type;
    while ($project_type->fetch) {
        # Dispatch the project type to one of the four display categories.
        my $cat = $ref =~ m/^Screen/                      ? \$type{screen}
                : $ref =~ m/^LF/                          ? \$type{inkjet}
                : $multi || $ref eq 'Scratch/WritingPads' ? \$type{multipage}
                :                                           \$type{singlepage};

        # Make sure our target is initialised then throw in the project type.
        $$cat = [] unless ref $$cat eq 'ARRAY';
        
        # Ugly I know, but it clutters the main page, and if we don't include
        # it in the description, it could clash with the non-largeformat
        # projects.
        $name =~ s/^Large Format //;
        push @$$cat, { id => $id, 'ref' => $ref, name => $name };
    }
    # Our project type order is actually defined to go down each one of the
    # three columns before it goes across. So we need to reorder the arrays.
    # for my $cat (keys %type) {
    #     my @cols = ([], [], []); # Display columns.
    #     
    #     for (my $i = 0; scalar @{$type{$cat}}; $i++) {
    #         push @{$cols[$i % 3]}, shift @{$type{$cat}};
    #     }
    #
    #     # Give the category's project types back in columnar order.
    #     $type{$cat} = [ @{$cols[0]}, @{$cols[1]}, @{$cols[2]} ];
    # }
    #
    
    return \%type;
}


sub create_display {
  my ($r, $log, $dbh, $cookie, $variable) = @_;

  # PREDEFINED PROJECTS
  #
  # Some pages had all the projects in a single form resulting in tens to
  # hundreds of blank ids with one actual id.
  my $pid = first { $_ } 
  map   { tr/0-9//cd; $_ } 
  $r->param('PredefinedProject') , $r->param('predefined');

  if ($pid) {
    # Populate the display with the old reference and comments.
    @$variable{qw(txtProjectReference txtComments type)} =
    $dbh->selectrow_array(q{
      SELECT strprojectreference, strcomments, lngprojecttype
      FROM tbl_projects 
      WHERE strstatus = 'predefined'
      AND lngprojectindex = ?
      }, undef, $pid
    );

    #FillInForm does a better job of encoding special characters than our standard ssi code.
    $variable->{__FillInForm}{txtProjectReference} = $variable->{txtProjectReference};
    delete $variable->{txtProjectReference};

    die "Predefined project ($pid) not found" 
    unless $pid && $variable->{type};

    $variable->{pms_colours_1} = $dbh->selectall_hashref(q{
      SELECT strname as name from tbl_service_specifications 
      WHERE lngprojectindex = ? And strName like 's0_pms%name'
      AND lngserviceindex IN ( select lngserviceindex FROM tbl_project_contents
      WHERE lngprojectindex = ?
      AND strservicetype = 'Printing'
      )
      ORDER by 1 DESC
      },'name', {}, $pid, $pid);
    $variable->{pms_colours_2} = $dbh->selectall_hashref(q{
      SELECT strname as name from tbl_service_specifications 
      WHERE lngprojectindex = ? And strName like 's1_pms%name'
      AND lngserviceindex IN ( select lngserviceindex FROM tbl_project_contents
      WHERE lngprojectindex = ?
      AND strservicetype = 'Printing'
      )
      ORDER by 1 DESC
      },'name', {}, $pid, $pid);

    # Tells the creation process which project to copy.
    $variable->{predefined}    = $pid;

    # If we're predefined, see if our services or quantity is locked
    # (fixed price and fixed item pricing).
    if ($pid) {
      $variable->{has_locked_quantity} =  $r->param('qty') ? 1 : has_locked_quantity($dbh, $pid);
      $variable->{has_locked_services} = has_locked_services($dbh, $pid);
    }

    $variable->{product_qty} = $r->param('qty');
    print STDERR "PRODUCT QTY , $variable->{product_qty} \n";

    # Go to Order process instead of project view if true.
    $variable->{create_to_order} = $r->param('create_to_order');

    # Allow user added services from the original predefined project.
    $variable->{__FillInForm}{project_service} = $dbh->selectcol_arrayref(q{
      SELECT strServiceType
      FROM tbl_Project_Contents
      WHERE lngProjectIndex = ?
      }, undef, $pid, );
  } # end if predefined

  #get the default line screen from the company profile.
  my $cust = new eprint::obj_customer($log, $dbh, $variable->{cust_id});
  $variable->{__FillInForm}{linescreen} = $cust->get('linescreen');

  # Allow PDF template selection to pass through
  $variable->{template} = $r->param('template') if $r->param('template');

  # ONLY PREDEFINDED ALLOWED CUSTOMERS
  #
  # If the user has been denied creating custom projects then
  # the create page takes them to the products page.
  if ($variable->{products_only} && !$pid) {
    $variable->{Redirect} =
    '/site_specific/main/products/products_overview.html';
    return OK;
  }

  # ADDITIONAL SERVICES
  #
  # We need to display all service types on create stage one and use the
  # mappings below to dynamic exclude certain ones by project type (JS).
  # Note: The project type will only be defined for predefined projects.
  @$variable{qw(categories category)} 
  = service_types_by_category(
    $dbh, $variable->{type}, $pid, $variable->{is_staff});

  $variable->{display_shipping} = $dbh->selectrow_array(q{
    SELECT count(*) from tbl_service_types WHERE strid = 'Shipping'
    AND ysnviewvisible = 'Y'
    });

  # All projects get cartons by default. TODO Move into DB.
  # $variable->{__FillInForm}{project_service} = (qw( PlainCartons ))
  #    if !$variable->{predefined};


  # PREDEFINED DONE
  #
  # Predefined projects have simple display needs.
  return OK if $variable->{predefined};

  # PRESS TYPES
  #
  # Weird ass way about building that data structure.
  $variable->{SelectedPress} = configuration::get_value(
    $log, $dbh, 'default_press_type' 
  );

  $variable->{SelectedPress} = $r->param('rdbPressType') if $r->param('rdbPressType');

  $variable->{press_types} = $dbh->selectall_arrayref(q{
    SELECT DISTINCT et.strname AS name, et.strid AS press
    FROM tbl_equipment e, 
    tbl_equipment_type et, 
    tbl_service_types s, 
    service_type_equipment se
    WHERE e.strtype = et.strid
    AND s.strid = 'Printing'
    AND s.lngindex = se.service_type
    AND se.equipment = e.lngindex
    ORDER BY et.strid
    }, { Slice => {} }, 
  );

  my %press_types;
  for my $hash (@{ $variable->{press_types} }) {
    $press_types{ $hash->{press} } = $hash;
  }

  @{ $variable->{press_types} } = ();

  foreach my $press (qw( press web screen inkjetprinter digital NoPrinting )) {
    push @{ $variable->{press_types} }, $press_types{ $press }
    if $press_types{ $press }
  }

  # PROJECT TYPES
  $variable->{project_type} = project_types($log, $dbh);

  # If we only have 1 Project Type Category && 
  # only 1 Project Type in that Category then select
  # it by default when loading the page.
  my @cats = keys %{$variable->{project_type}};
  if ( scalar @cats == 1 
    && @{$variable->{project_type}{$cats[0]}} == 1
  ) {
    $variable->{__FillInForm}{rdbProjectType} =
    ${$variable->{project_type}{$cats[0]}}[0]->{id};
  };

  # NOTE: Pushing the mapping onto an array instead of creating a secondary
  # hash yields a data structure that serialised down to less than half the
  # hash. However we then have to convert in JS or it's cumbersome to work
  # with. Not sure where the better tradeoff lies.

  # The project types allowed depends on the press type selected. TODO Use
  # press id instead of the string.
  my $sth = $dbh->prepare(q{
    SELECT e.strid, p.project_type
    FROM project_type_by_press p, tbl_equipment_type e
    WHERE e.lngindex = p.press});
  $sth->execute();
  my %by_press;
  while (my ($press, $project_type) = $sth->fetchrow_array) {
    $by_press{$press} = {} unless exists $by_press{$press};
    $by_press{$press}{$project_type} = 1;
  }
  $variable->{press_to_project} = encode_json(\%by_press);

  # SERVICE EXCLUSIONS
  #
  # Certain services can't be performed by various presses or on various
  # project types. Send mappings to the javascript so it can hide services
  # when it needs to.

  # Get the project type to group mappings
  $variable->{project_groups} = encode_json({@{
      $dbh->selectcol_arrayref(q{
      SELECT lngindex, lnggroup FROM tbl_projecttypes
      }, { Columns => [1,2] }) 
      }});

  # Assemble a list of service type exclusions per group.
  $sth = $dbh->prepare(q{SELECT * FROM service_type_by_project_group});
  $sth->execute();
  my %grouped;
  while (my ($group, $service_type) = $sth->fetchrow_array) {
    $grouped{$group} = [] unless exists $grouped{$group};

    push @{ $grouped{$group} }, $service_type;
  }
  $variable->{service_types_by_group} = encode_json(\%grouped);

  return OK;
}

# We build a list of services grouped by category. TODO Doing more of this
# in the DB would probably be faster.
sub service_types_by_category {
    my ($dbh, $project_type, $pid, $is_staff) = @_;

    my ($categories, %services_in);

    $categories = $dbh->selectall_arrayref(q{
        SELECT lngindex AS id, strid AS ref, strname AS name 
        FROM tbl_service_categories
        WHERE strid <> 'Printing'
        ORDER BY lngsort
    }, { Slice => {} });

    # If a project type is passed, limit the services displayed to only those
    # that can be preformed on that project type.
    my $clause = $project_type ? q{
        AND lngindex NOT IN (
            SELECT service_type 
            FROM service_type_by_project_group s, tbl_projecttypes p 
            WHERE p.lnggroup = s.project_group 
              AND p.lngindex = ? ) 
    } : '';

    # NOTE: Binding types are not shown here as they are mutually exclusive,
    # can only be applied to multipage project, and as such can be changed
    # on the multipage project page.
    my $services = $dbh->prepare_cached(qq{
        SELECT DISTINCT lngindex       AS id, 
                        strid          AS ref, 
                        strname        AS name, 
                        strdescription AS description
        FROM tbl_service_types t JOIN 
             service_type_equipment e ON (lngindex = service_type)
        WHERE ysncreatevisible = 'Y'
       --   AND strtype <> 'bind'
          AND strcategory = ?
          $clause
        ORDER BY strname
    });

    # If we're a predefined project only certain services many be allowed.
    my $allowed = $pid ? allowed_services($dbh, $pid) : undef;

    # Get the list of service types in each category TODO Get everything in
    # one query and use the group() util function.
    for my $cat (@$categories) {
      print STDERR "qq{
        SELECT DISTINCT lngindex       AS id, 
                        strid          AS ref, 
                        strname        AS name, 
                        strdescription AS description
        FROM tbl_service_types t JOIN 
             service_type_equipment e ON (lngindex = service_type)
        WHERE ysncreatevisible = 'Y'
       --   AND strtype <> 'bind'
          AND strcategory = '$$cat{ref}'
          $clause for $project_type
        ORDER BY strname
 \n";
        my @services 
            = @{ $dbh->selectall_arrayref($services, {Slice => {}}, 
                $cat->{ref},
                $project_type ? $project_type : ()
            ) };

        # Don't show disallowed services for predefined projects.
        @services = grep { exists $allowed->{ $_->{id} } } @services
            if $allowed && !$is_staff;

        $cat->{services} = $services_in{ lc $cat->{ref} } = \@services;
    }

    # Remove any categories that don't have services.
    return [ grep { @{ $_->{services} } } @$categories ], \%services_in;
}


# Just like create project, all this has to do is display the page /main/proj/edit
sub edit_display {
  my ( $r, $log, $dbh, $cookie, $variable ) = @_;

  # GENERAL PROJECT INFORMATION
  #
  my $pid = $r->param('pid') || $r->param('ProjectIndex');

  $variable->{ProjectIndex} = $pid;

  # TODO: Replace w/ selectrow_hashref.
  @$variable{qw( txtProjectReference  design        file_type
  txtQuantity1         txtQuantity2  txtQuantity3 
  txtComments          ShipDate 
  project_type         RequiredDate txtInvoiceComments
  )} = $dbh->selectrow_array(q{
    SELECT strProjectReference,  strDesign,    strprograms,
    intQuantity1,         intQuantity2, intQuantity3, 
    strComments,          dtmShipDate,
    lngprojecttype,       to_char(dtmRequiredDate, 'MM/DD/YYYY'),
    strInvoiceComments
    FROM tbl_Projects WHERE lngProjectIndex = ?
    }, {}, $pid);
  #print STDERR "HAVE INVOCIE COMMENTS: $variable->{txtInvoiceComments} \n";

  $variable->{txtProjectReference} =~ s/'/&apos;/g;
  $variable->{txtProjectReference} =~ s/"/&quot;/g;

  $variable->{is_multipage} = is_multipage($log, $dbh, $pid);

  $variable->{has_locked_quantity} 
  = $variable->{is_staff}  ? 0 : has_locked_quantity($dbh, $pid);

  $variable->{__FillInForm}{project_service} = $dbh->selectcol_arrayref(q{
    SELECT strServiceType
    FROM tbl_Project_Contents
    WHERE lngProjectIndex = ?
    }, undef, $pid, );

  push @{ $variable->{__FillInForm}{project_service} } , @{ $dbh->selectcol_arrayref(q{
  SELECT strvalue
  FROM tbl_service_specifications
  WHERE lngProjectIndex = ? AND strName = 'ShippingType'
  }, undef, $pid) };

  # DESIGN FORMAT
  # 
  # Map the design to the file type if we're a legacy "electronic file".
  # Give the current design an HTML string to select it. Yucky.
  $variable->{design} = $variable->{file_type} 
  if $variable->{design} eq 'ElectronicFile';

  $variable->{format}{ lc $variable->{design} } = 'selected="selected"';    

  @$variable{qw(categories category)} 
  = service_types_by_category(
    $dbh, $variable->{project_type}, $pid, $variable->{is_staff}
  );

  $variable->{display_shipping} = $dbh->selectrow_array(q{
    SELECT count(*) from tbl_service_types WHERE strid = 'Shipping'
    AND ysnviewvisible = 'Y'
    });

  return OK;
}


# Extract the design, program, and optional user specified program from the
# request object.
sub design_format {
    my $r      = shift;
    my $format = $r->param('format') || 'PDF'; # Default to PDF.
    my ($file_type, $other);

    # If we're not a physical media, we're a file; and format is our file
    # type.
    if ($format ne 'PlatesSupplied' and $format ne 'FinalFilm') {
        $file_type = $format; 
        $format    = 'Electronic File';           # Legacy value.
        $other     = $r->param('other_program') 
            if defined $file_type and $file_type eq 'Other';
    }
	if ( $r->param("filetypes") ) {
		$format = $r->param('filetypes') eq 'Hard Copy Only' 
					? $r->param("filetypes")
					: $r->param("filetypes") . " , " . $format;
	}

    return $format, $file_type, $other;
}


# Creates a new project, first clearing out any previous projects.
sub create_process {
    my ( $r, $log, $dbh, $cookie, $var, $qtys, $predefined, 
		 $projref, $press_type, $project_type 				) = @_;

    die "You must specify a project name"              unless $projref;
    die "You must specify at least the first quantity" unless $qtys->[0];

	$project_type = $project_type  || $r->param('rdbProjectType');
	$press_type   = $press_type    || $r->param('rdbPressType');

    # if we are going to select a predefined project then we don't want to
    # create a new project yet.
    if ( $r->param('rdbMode') eq 'Predefined' ) {
        $var->{Redirect} = '/main/proj/templates/brochures.html';
        return;
    }

	my $project_ref;
	my $templateurl;

    # Add the project type directly to the project now, not in service
    # specifications on the 'Print' task.
    ($project_type, $project_ref, $templateurl) = $dbh->selectrow_array(q{
        SELECT lngindex, strid, strtemplateurl
        FROM tbl_projecttypes
        WHERE lngindex = ?
    }, undef, $project_type)  if $project_type;

   
    $press_type = scalar $dbh->selectrow_array(q{
        SELECT lngindex
        FROM tbl_equipment_type
        WHERE strid = ?
    }, undef, $press_type);


    my $user_name = scalar $dbh->selectrow_array(q{
        SELECT strfirstname ||' '|| strlastname
        FROM tbl_customer_users
        WHERE lnguserid = ?
    }, {}, $$var{'user_id'});

    # IMAGE/DESIGN MEDIA TYPE
    #
    # The project design can be supplied by some type of electronic file, as
    # film for 'convential' image-setting, or as pre-made plates. The
    # format is a combination of the available file types and the media
    # options.
    my ($design, $program, $other) = design_format($r);

    # Create the project.
    insert(
        $log, $dbh, 'tbl_Projects',
        lngprojecttype      => $project_type,
        lngCustomerID       => $var->{'cust_id'},
        lngUserIndex        => $var->{'user_id'},
        strProjectReference => $projref,

        strComments         => $r->param('txtComments') . '' ,
        
        intQuantity1        => $qtys->[0],
        q2        			=> $qtys->[1],
        q3        			=> $qtys->[2],

        strStatus           => 'uncalculated',
        lngPressType        => $press_type,
        strdesign           => $design,
        strprograms         => $program,
        strotherprograms    => $other,
        dtmCreationDate     => 'NOW()',
        dtmLastModified     => 'NOW()',
        strCreatedBy        => $user_name,
		rfq_only			=> $r->param('rfq_only') ? $r->param('rfq_only') : 0,
        strInvoiceComments  => $r->param('txtInvoiceComments') || undef,
		linescreen			=> $r->param('linescreen') || undef,
		digifed				=> ($r->param('DigiFed') || 0),
    );

    my $pid;

    # Get the new project's ID. Replace with last_insert_id when avail.
    $pid = $dbh->selectrow_array(
        q{SELECT currval('lngprojectindex_seq')}
    );

    # If we don't get a valid PID something has gone very wrong.
    die "Couldn't create project" unless $pid;

    # Special case for project type
    insert_project_type($r, $log, $dbh, $pid, $project_ref) 
        unless $project_ref eq 'InventoryCheckOut';
    
    # Add any additional services the user requested.
    modify_services($r, $log, $dbh, $cookie, $var, $pid);

    return $pid;
}


sub modify_services {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;
    
    my $modified = 0;

    $variable->{PressType} = get_press_type($log, $dbh, $pid);

    # PROJECT SERVICES
    #
    # The user has just (re)defined which prepress, bindery, and speciality
    # service types they want in their project. Compare against the list of
    # project services and insert or delete as required.
    
    # Get the list of services the user wants.
    my %service;
    @service{ $r->param('project_service') } = (undef);

    # Get all the service types and join it to the list of project services in
    # the current project. Anything that is NEEDED or SUGGESTED will not
    # appear in the overall list at all.
    my $sth = $dbh->prepare(q{
        SELECT p.lngserviceindex AS sid, t.strid AS name
        FROM      ( SELECT lngserviceindex, strservicetype, lngneedlevel
                    FROM tbl_project_contents
                    WHERE lngprojectindex = ?) p
        FULL JOIN tbl_service_types t ON (p.strservicetype = t.strid),
                  ( SELECT DISTINCT service_type
                    FROM service_type_equipment ) s
        WHERE t.lngindex = s.service_type
          AND ysncreatevisible = 'Y'
        --  AND strtype <> 'bind'
          AND (p.lngneedlevel IS NULL OR p.lngneedlevel = 0)
        ORDER BY strname
    });
    $sth->execute($pid);

    my ($sid, $name);
    $sth->bind_columns(\$sid, \$name);

    # Insert or delete as needed (we use remove just incase).
    while ($sth->fetch) {
print STDERR "PRICING MODIFY SERVICE: SID: $sid NAME: $name HAVE:  $service{$name} \n";
        # If the project service exists in the project but isn't in the user's
        # service list we'll remove it from the project.
        if ($sid && ! exists $service{$name}) {
            remove_service($log, $dbh, $pid, $sid);
            $modified = 1;
        }
        # If the name is in the list but the service type isn't in the
        # project, we'll insert it.
        elsif (exists $service{$name} && ! $sid) {
            insert_service($log, $dbh, $pid, $name);
            $modified = 1;
        }
    }

    # Handle the extra shipping services that are not real service types.
    foreach my $type ( qw{Project Samples Proofs} ) {
        if ( exists $service{"Shipping_$type"}) {
            add_shipping($log, $dbh, $pid, $type);
            $modified = 1;
        } 
        else {
            remove_shipping($log, $dbh, $pid, $type);
        }
    }

    return $modified;
}

sub add_shipping {
    # Insert a Shipping Service and a couple of Specs.
    my ($log, $dbh, $pid, $type, %atrib ) = @_;

    my ($sid) = $dbh->selectrow_array(q{
            SELECT lngserviceindex from tbl_service_specifications 
            WHERE lngserviceindex IN ( SELECT lngserviceindex FROM tbl_project_contents
                                        WHERE lngprojectindex = ? AND strservicetype = 'Shipping' )
            AND strName = 'txtServiceDescription' AND strValue = ?
    },undef,$pid, $type);

    return if $sid;

    $sid = insert_service( $log, $dbh, $pid, 'Shipping', { user_requested => 1} );
    
    # txtServiceDescription is used for the project view display
    # rdbShippingContents is used for the radio btn on the Shipping Page
    # ShippingType is used by the Project Edit Page
    eprint::service::insert_service_specs( $log, $dbh, $pid, $sid,( 
        txtServiceDescription => $type,
        rdbShippingContents   => $type eq 'Samples' ? 'Other' : $type,
        ShippingType          => 'Shipping_'.$type
    ));

    eprint::service::insert_service_spec( $log, $dbh, $pid, $sid, 'txtShipmentWeight' , '5')
        if $type eq 'Samples';

    my $shipper = configuration::get_value( $log, $dbh, $type.'ShippingOverride');
    if ($shipper) {
        eprint::service::insert_service_specs($log,$dbh,$pid,$sid, ( 
            chkOverrideShipper1 => 'Y',
            chkOverrideShipper2 => 'Y',
            chkOverrideShipper3 => 'Y',
            ddmShipVia1 => $shipper,
            ddmShipVia2 => $shipper,
            ddmShipVia3 => $shipper,
        ));
    }
    return $sid;
}

sub remove_shipping {
    # This shipping type was not requested so remove any instances of it.
    my ( $log, $dbh, $pid, $type ) = @_;
        my $sth = $dbh->prepare( q{
            SELECT lngserviceindex from tbl_service_specifications 
            WHERE lngserviceindex IN ( SELECT lngserviceindex FROM tbl_project_contents
                                        WHERE lngprojectindex = ? AND strservicetype = 'Shipping' )
            AND strName = 'txtServiceDescription' AND strValue = ?
        });
        $sth->execute($pid, $type);
        while (my $sid = $sth->fetchrow_array) {
            delete_service($log, $dbh, $pid, $sid);
        }
}



# Creates a new project by copying a predefined one and recalculating it
# (possibly changing the quantities).
sub create_project_from_predefined {
    my ($r, $log, $dbh, $cookie, $variable, $qtys, $source, $name) = @_;
    no warnings qw(uninitialized);

	die("Can not make project. Project Ref: $name, Product: $source") unless $source && $name;

    # Make sure the project exists and is predefined.
    die "Project ($source) doesn't exist or isn't a predefined project."
        unless $dbh->selectrow_arrayref(q{
            SELECT true FROM tbl_projects 
            WHERE strstatus = 'predefined' AND lngprojectindex = ?
        }, undef, $source);


    # Copy the project.
    my ($destination) = copy_project($dbh, $variable, $source, {
            name    => $name,
            comment => ($r->param('txtComments')         || ''),
			prod => ($source)
        }
    ) or die "Error copying prefedined project ($source)";


    # If the project is locked copying is all we have to do.
    return $destination if has_locked_quantity($dbh, $source);

    # Otherwise reset the project for recalculation.
    update($log, $dbh, 'tbl_projects', "lngProjectIndex = $destination", 
        strstatus => 'uncalculated'
    );

    # If the design was supplied via the form (predefined projects) override
    # the old with the selected one. TODO Make sure preflight isn't a locked
    # service before changing the format.
    if ($r->param('format')) {
        $dbh->do(q{
            UPDATE tbl_projects
            SET strdesign        = ?,
                strprograms      = ?,
                strotherprograms = ?
            WHERE lngprojectindex = ?
        }, undef, design_format($r), $destination);
    }


	$qtys = [$r->param('product_qty'), 0, 0] if $r->param('product_qty');

    die "At least one quantity must be defined" unless $qtys->[0];

    # Update the project itself.
    $dbh->do(q{
        UPDATE tbl_projects
        SET intquantity1 = ?,
            intquantity2 = ?,
            intquantity3 = ?
        WHERE lngprojectindex = ?
    }, undef, @{$qtys}, $destination);


    # Each sevice that makes or modifies the project needs to be updated.
    my $specs = $dbh->prepare(q{
        UPDATE tbl_service_specifications
        SET strvalue = ?
        WHERE strname = 'txtQuantity' || ?::char(1)
          AND lngprojectindex = ?
    });

    for my $i (0..1) {
        next unless $qtys->[$i] && $qtys->[$i] > 0;
        $specs->execute($qtys->[$i], $i+1, $destination);
    }

    # Support for Custom Fields on Project Create page to insert
    # pms colours into the printing services.
    foreach my $p ( $r->param() ) {
        next unless $p =~ /pms.*name/;
        $dbh->do(q{
            UPDATE tbl_service_specifications SET strvalue = ?
            WHERE strname = ? AND lngserviceindex in (
                SELECT lngserviceindex FROM tbl_project_contents
                WHERE lngprojectindex = ? and strservicetype = 'Printing'
            )
        }, undef, $r->param($p), $p, $destination);
    
    }

    return $destination;
}


sub api_xml {
	use XML::Simple;
    my ( $r, $log, $dbh, $var ) = @_;
	my ($f) = $dbh->selectrow_array(q{
		SELECT xml FROM src_req WHERE id = ?
	}, undef, $r->param('id'));

	open(MYFILE, $f);
	while (<MYFILE>) 
	{
		$var->{xml} .= $_;
	}
	close(MYFILE);

	my $x = XMLin($var->{xml});
	my $y = XMLout($x);
	print STDERR "MY Y: $y \n";
	$var->{xml} = $y;
	
}

sub api_list {
    my ( $r, $log, $dbh, $var ) = @_;

	my @params = $r->param();
	my $sth = $dbh->prepare(q{
		UPDATE src_req set pid = ? WHERE id = ?
	});

	map { $sth->execute($r->param($_), $1) if $_ =~ /pid_(\d+)/ and $r->param($_) } @params;

print STDERR "API LIST START **** \n\n";

    ssi::get_dates($r, $log, $dbh, $var);

	my $sql  = 'SELECT * FROM src_req WHERE 1 > 0 ';
	   $sql .= ' AND pid IS NULL ' unless $r->param('ddmStatus') eq 'ALL';
	   $sql .= ' ORDER by id desc';

	$var->{reqs} = $dbh->selectall_arrayref($sql, { Slice => {} } );

}

sub is_integer {
   defined $_[0] && $_[0] =~ /^[+-]?\d+$/;
}

# Display a list of projects on the project history page.
sub history_list {
  my ( $r, $log, $dbh, $variable, $max_records ) = @_;

  # Handle project deletion.
  if ($r->param('action') eq 'Delete') {
    my $error;
    $error .= delete_project($log, $dbh, $variable, $_) 
    for $r->param('delete');

    return misc::error( $log, $dbh, $variable, 'Error', $error ) if $error;
  }

  my $ref = lc($r->param('pid'));

  my $is_num = is_integer($ref); 

  my $redirect;
  my $cust;
  my $pid;
  ($pid, $cust) = $is_num ? $dbh->selectrow_array(q{
    SELECT lngprojectindex, lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $ref) : undef;

  if ( $pid ) {
    $redirect = "/main/proj/proj_view.html?pid=$pid";
  }

  $ref =~ /(\d*)/;

  my $order;
  my $ocust;
  ($order, $ocust)	= $1 ? $dbh->selectrow_array(q{
    SELECT lngorderid, lngcustomerid FROM tbl_orders WHERE lngorderid = ?
    }, undef, $1) : undef;

  if ( $order ) {
    $redirect = "/main/order/order_history_details.html?order_id=$order";
    $cust = $ocust;
  }

  if ( $redirect ) {
    die("have cust: $cust, $variable->{cookie} ") unless $cust;
    eprint::login::select_customer( $r, $log, $dbh, $variable->{cookie}, $variable, $cust );
    $variable->{Redirect} = $redirect;
    return;
  }

  print STDERR "HAVE STUFF: $ref ; $is_num -- PID: $pid \n";

  # Current date.
  my ($year, $month, $day) = (localtime(time))[5,4,3];

  $year  += 1900;
  $month += 1;

  # Default start is a month ago.
  my $sYear  = $r->param('ddmStartYear')  || $year;
  my $sMonth = $r->param('ddmStartMonth') || $month - 1;
  my $sDay   = $r->param('ddmStartDay')   || $day;

  # If we're not using a user specified date and the current date is
  # january, default back to the december of last year.
  if (!$r->param('ddmStartMonth') && $month <= 1) {
    $sYear = $year - 1;
    $sMonth = 12;
  }

  # Default end is today (can't search future)
  my $eYear  = $r->param('ddmEndYear')  || $year;
  my $eMonth = $r->param('ddmEndMonth') || $month;
  my $eDay   = $r->param('ddmEndDay')   || $day;

  ssi::get_start_end_dates( 
    $log, $dbh, $variable, $sYear, $sMonth, $sDay, $eYear, $eMonth, $eDay
  );

  my $status = $r->param('ddmStatus');

  # Status search dropdown.
  $variable->{ddmStatus} = ssi::fill_drop_down($log, $dbh, qq{
    SELECT DISTINCT strStatus, strStatus 
    FROM tbl_Projects 
    WHERE strStatus != '' 
    AND strStatus != 'Deleted' 
    AND lngCustomerID = $variable->{cust_id}
    ORDER BY strStatus
    }, $status );

  my $clause = 'AND strstatus = ' . $dbh->quote($status) if $status;

  #my $user_clause = "AND lnguserindex = $variable->{user_id} " if $variable->{user_type} eq 'C' && $variable->{user_id} ne '293';
  my $user_clause = " ";

  my $limit  = "LIMIT $max_records"                      if $max_records;

  my @data = ($variable->{cust_id}, $variable->{StartDate}, $variable->{EndDate});

  my $ref_clause = $ref ? q{ AND lower(regexp_replace(strprojectreference, '\s','','g')) ~ regexp_replace(?, '\s','','g') } : '';
  push @data, $ref if $ref;

  # Get the list of projects respecting any search params the user entered.
  $variable->{projects} = $dbh->selectall_arrayref(qq{
    SELECT p.lngprojectindex                                AS pid,
    p.strprojectreference                            AS reference,
    p.strstatus                                      AS status,
    to_char(p.dtmcreationdate, 'MM/DD/YYYY')         AS create_date,
    to_char((p.dtmexpiredate - NOW()),'dd')::int < 1 AS expired,
    o.lngorderid IS NOT NULL                         AS is_ordered,
    o.lngorderid				                        AS order_id,
    CASE WHEN o.intquantityindex IS NULL 
    THEN 1 ELSE o.intquantityindex 
    END 										AS order_qty,	
    (SELECT MAX(lngquoteid) FROM tbl_quote_details 
    WHERE tbl_quote_details.lngprojectindex = p.lngprojectindex) AS quote_id,
    p.intquantity1                                  AS qty,

    (SELECT strname FROM tbl_equipment_type et
    WHERE et.lngindex = p.lngpresstype)   		AS press_type



    FROM tbl_projects p LEFT JOIN tbl_order_contents o USING (lngprojectindex)
    WHERE p.lngcustomerid = ?
    AND p.strstatus != 'Deleted'
    AND date(p.dtmcreationdate) BETWEEN date(?)
    AND date(?)
    $clause
    $user_clause
    $ref_clause
    ORDER BY p.lngProjectIndex DESC
    $limit
    }, 
    { Slice => {} }, @data); 

  map {
    my @prices = eprint::project::project_price($log, $dbh, $_->{pid});
    $_->{price} = $prices[0];
  } @{$variable->{projects}};

  $variable->{search} = $r->param('pid');

  #use Data::Dumper;
  #print STDERR "PROJ DUMPER " , Dumper($variable);
  return OK;
}

sub delete_project {
    my ($log, $dbh, $variable, $pid) = @_;

    my $id = $dbh->selectrow_array(q{
        SELECT lngcustomerid FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

    return 'Project does not exist.' unless $id; # Project doesn't exist.

    # The user is only allowed if they're the owner or an employee/admin.
    return "You don't have permission to modify this project."
        unless $variable->{user_type} =~ /^[AE]$/ 
            || $id == $variable->{cust_id};

	#****************************** This code is broken > 1 allows projects to be delted *******************************
	#Projects show not be allowed to be deleted after order or quote.
			
    # Check to see if the project is in a quote or order.
    my $is_ordered = $dbh->selectrow_array(q{
        SELECT count(*) > 1 FROM tbl_order_contents WHERE lngprojectindex = ?
    }, undef, $pid);

    my $is_quoted  = $dbh->selectrow_array(q{
        SELECT count(*) > 1 FROM tbl_quote_details  WHERE lngprojectindex = ?
    }, undef, $pid);

    eprint::inventory::delete_by_project($log, $dbh, $pid);

    # TODO Just catch the ref. integrity error instead of the two check queries.

    # Only mark the project as no longer visible if it is in either a quote or
    # order, otherwise it may be safely removed.
	
	#Disable deleting until bugs are fixed.
	#Projects are being removed from db.
	

	#my $statement = ($is_ordered || $is_quoted) 
	#    ? q{ UPDATE tbl_projects SET strstatus = 'Deleted' WHERE lngprojectindex = ? }
	#    : q{ DELETE FROM tbl_projects                      WHERE lngprojectindex = ? };

	#my $statement =  q{UPDATE tbl_projects SET strstatus = 'Deleted' WHERE lngprojectindex = ? };


	#my $deleted = $dbh->do($statement, undef, $pid);

    return;
}

#remove all projects associated with a customer
sub delete_customers_projects {
  my ($log, $dbh, $id) = @_;
  my $variable = {'user_type' => 'A'};

  $id =~ tr/0-9//cd;

  # die "Invalid project ID." unless $id;
  return unless $id;

  my $projects = $dbh->selectcol_arrayref("select lngprojectindex from tbl_projects where lngcustomerid = ?", undef, $id);
  for my $project (@$projects) {
    delete_project($log, $dbh, $variable, $project);
  }
}

#remove all projects associated with a user
sub delete_users_projects {
  my ($log, $dbh, $id) = @_;
  my $variable = {'user_type' => 'A'};

  $id =~ tr/0-9//cd;

  # die "Invalid project ID." unless $id;
  return unless $id;

  my $projects = $dbh->selectcol_arrayref("select lngprojectindex from tbl_projects where lnguserindex = ?", undef, $id);
  for my $project (@$projects) {
    delete_project($log, $dbh, $variable, $project);
  }
}

sub summary_header {
    my $r        = shift;
    my $log      = shift;
    my $dbh      = shift;
    my $variable = shift; # Special SSI variable
    my $pid      = shift; # Project ID

    # This could be done much cleaner.
    @$variable{qw(
        ProjectIndex ProjectReference Comments RequiredDate CreationDate 
        txtQuantity1 txtQuantity2 txtQuantity3 ProjectStatus ddmDesign CreatedBy 
        CompanyName 
    )} = $dbh->selectrow_array(q{
        SELECT lngProjectIndex,
               strProjectReference, 
               strComments, 
               to_char(dtmCreationDate, 'MM/DD/YYYY'), 
               intQuantity1, intQuantity2, intQuantity3, 
               strStatus, 
               strDesign,
           strCreatedBy,
               ( SELECT strCompanyName 
                 FROM tbl_Customer 
                 WHERE tbl_CUstomer.lngCUstomerID = tbl_Projects.lngCUstomerID ),
        FROM tbl_Projects 
        WHERE lngProjectIndex = ?
    }, undef, $pid);

    return 1;
}

sub edit_process {
    my ( $r, $log, $dbh, $cookie, $variable, $pid, $add_qty, $qtys ) = @_;

    $pid =~ tr/0-9//cd;

    my $modified = 0;

    # BASIC PROJECT INFO
    #
    # Update the project name and mode.
    update( $log, $dbh, 'tbl_Projects', "lngProjectIndex='$pid'", 
        strComments         => ($r->param('txtComments') or undef),
        strInvoiceComments  => ($r->param('txtInvoiceComments') or undef),
        dtmLastModified     => 'NOW()',
    );

    update( $log, $dbh, 'tbl_Projects', "lngProjectIndex='$pid'", 
        strProjectReference => $r->param('txtProjectReference')
	) if $r->param('txtProjectReference');

    update( $log, $dbh, 'tbl_Projects', "lngProjectIndex='$pid'", 
        lngpresstype => $r->param('rdbPressType')
    ) if $r->param('rdbPressType');

    # QUANTITIES
    #
    if (!has_locked_quantity($dbh, $pid) || $variable->{is_staff}) {
        # If the quantities have changed we need a full recalculation.
        my @old; @old[1..3] = get_quantities($log, $dbh, $pid);

        # Clean the new quantities and remove any blanks. None of this crap would
        # be necessary if we just used HTML elements properly.
        my @new;
		if ( defined $qtys ) {
print STDERR "USE NEW QTYS: @{$qtys} \n";
			@new = (undef,@{$qtys});
		} else {
print STDERR "USE NEW QTYS FROM PARAM:  \n";
			@new = grep { defined $_ and $_ > 0     }
					  map  { $r->param("txtQuantity$_") =~ /(\d+)/; $1 } 
						   1..3;
			@new = (undef, map { $new[$_] || 0 } 0..2);
		}

        # Compare the new and old quantities and update statuses if needed.
        for my $i (1..3) {
            # If the quantities are different update them and set the flag.
            if ($new[$i] != $old[$i]) {
                update($log, $dbh, 'tbl_Projects', "lngProjectIndex = $pid",
                    "intquantity$i" => $new[$i],
                );

                # Horribly we just clobber all the custom quantities without
                # ever informing the user. TODO: Bug 1646
                update($log, $dbh, 'tbl_service_specifications', 
                    "lngprojectindex = $pid AND strname = 'txtQuantity$i'",
                    strvalue => $new[$i],
                );
                update($log, $dbh, 'tbl_service_specifications', 
                    "lngprojectindex = $pid AND strname = 'hdnQuantity$i'",
                    strvalue => $new[$i],
                );
				my $sq = $dbh->selectrow_array(q{
					SELECT Count(*) FROM tbl_service_specifications 
					WHERE lngprojectindex = ? AND strname ~ 'add_qty1'
				}, undef, $pid);
print STDERR "MY QTYS: $sq \n";

				if ( $sq == 1 ) {
					update($log, $dbh, 'tbl_service_specifications', 
						"lngprojectindex = $pid AND strname ~ 'add_qty$i'",
						strvalue => $new[$i],
					);
				} else { 

					my $sth = $dbh->prepare(q{ DELETE FROM tbl_service_specifications
						WHERE strname ~ 'add_qty' 
						AND lngprojectindex = ?
					});
					$sth->execute($pid);
			

					$dbh->do(q{ UPDATE tbl_project_contents SET strstatus = 'uncalculated'
						WHERE lngprojectindex=? AND strservicetype = 'Shipping' }, {}, $pid );
				}
               
                $modified = 2; # Full recalculate
            }
        }
    }

    # IMAGE/DESIGN MEDIA TYPE -- PREFLIGHT
    #
    # The project design can be supplied by some type of electronic file, as
    # film for 'conventional' image-setting, or as pre-made plates. If we're
    # changing between any of these types we need to recalculate everything as
    # all the plate charges are currently in printing.

    # The previous design selected.
    my ($design, $program) = $dbh->selectrow_array(q{
        SELECT strdesign, strprograms FROM tbl_projects WHERE lngprojectindex = ?
    }, {}, $pid);

    # The current user selected format.
    my ($format, $file_type, $other) = design_format($r);
    
    # Update the design and program information if any of it's changed.
    update($log, $dbh, 'tbl_projects', "lngprojectindex = $pid",
        strdesign        => $format,
        strprograms      => $file_type,
        strotherprograms => $other,
    );

    # See if the overall design media has changed, if so recalculate. TODO:
    # Just fiddle with the preflight project service if we're only changing
    # the file types.
    $modified = 2 if $design ne $format or $program ne $file_type;

    # TODO: Are there any actions other than recalculating we need to take
    # when changing between supplied media?

    my $services_modified
        = modify_services($r, $log, $dbh, $cookie, $variable, $pid) if !$add_qty;;

    # The level of recalculation required.
    return $modified > $services_modified ? $modified : $services_modified;
} 

# User removal of services, marks as removed instead of actually deleting them
# unless they're NOT_NEEDED.
sub remove_service {
    my ($log, $dbh, $pid, $sid) = @_;

	#Testing to see what happens if we don't build, other than doing less work??
#$dbh->do(q{update tbl_projects set build = true where lngprojectindex = ?}, undef, $pid);
    
    # Until we care about bindery only projects, you're just not allowed to
    # delete the 'Printing' service. TODO: We shouldn't be able to delete the
    # last signature and commit the transaction (if we actually used them).
    return 0 if $sid == get_print_container(@_);


    # Whether we remove or delete is based on the need level of the service.
    my $need = get_need($log, $dbh, $sid);

	print STDERR "REMOVE SERVICE $pid, $sid : Need: $need \n ";

    # If it's not needed we can just delete it outright.
    if ($need != NEEDED) {
        delete_service(@_) 
    }
    # If the project service is marked as NEEDED we don't delete it but
    # instead set its removed flag. 
    else {
		my $removed = $dbh->selectrow_array(q{
			SELECT ysnremoved FROM tbl_project_contents WHERE lngprojectindex = ? and lngserviceindex = ?
		}, undef, $pid, $sid );

	print STDERR "REMOVE SERVICE $pid, $sid : Need: $need REMOVED: $removed Before update \n ";

		my $status = $removed ? 'FALSE' : 'TRUE';

		$dbh->do(qq{ UPDATE tbl_project_contents 
					SET ysnremoved = $status
					WHERE lngprojectindex = ? AND lngserviceindex = ?
		}, undef, $pid, $sid);
    }

    # NOTE: Until we finish the changes to all the various service checks and
    # displays for removal (not deletion) of SUGGESTED services they'll just
    # be deleted like NOT_NEEDED project services. 
    # 
    #    # If the project service is SUGGESTED it's no longer part of the
    #    # calculations when it's removed so we can delete all its specs.
    #    # $dbh->do(q{ DELETE FROM tbl_service_specifications
    #    #             WHERE lngprojectindex = ? AND lngserviceindex = ?
    #    # }, undef, $pid, $sid) if $need == SUGGESTED;

    return 1;
}


sub delete_service {
    my ($log, $dbh, $pid, $sid) = @_;

    # Services down the line need to be adjusted due to our departure. As
    # we're leaving the chain we want to act like we're completed (and we are
    # 'finished' in a sense ;) so no service depends on us any longer.
    set_status($log, $dbh, $pid, 'calculated', $sid);
    recalc_dependencies($log, $dbh, $pid, $sid);

    # Now we can fade into the sunset. 
    $dbh->do(q{ 
        DELETE FROM tbl_project_contents WHERE lngserviceindex = ?
    }, undef, $sid);

    return 1;
}


sub mark_project_complete_if_necessary {
    my ( $log, $dbh, $pid ) = @_;

    # This should never be called without a $pid, for now we just ignore
    # it if it's called without one though we _should_ be doing some assertion
    # checking and figuring out why it's being called without one.
    return unless defined $pid;
    
    # If no services are left in statuses other than those listed below, the
    # we assume the project is complete. Stuff like this should be done with
    # triggers.
    my $complete = $dbh->selectrow_array(qq{
        SELECT count(*) = 0
        FROM tbl_Project_Contents
        WHERE lngProjectIndex = ?
          AND strStatus NOT IN ( 'calculated',    'Complete', 
                                 'In Production', 'Pending Deposit' , 'Waiting For Files' )
    }, undef, $pid);
    
    if ( $complete ) {
        $dbh->do(q{
            UPDATE tbl_projects 
            SET strstatus = 'Unordered'
            WHERE lngprojectindex = ? AND strStatus = 'uncalculated'
        }, undef, $pid);
    } 
    else {
        $dbh->do(q{
            UPDATE tbl_projects SET strstatus = 'uncalculated' WHERE lngprojectindex = ? 
        }, undef, $pid);
    }

    return $complete;
}

sub price_breakdown {
    my ($r, $log, $dbh, $variable) = @_;

    my $pid = $variable->{pid} = $r->param('ProjectIndex');
    my $sid = $variable->{sid} = $r->param('ServiceIndex');

    $variable->{ProjectIndex} = $pid;


    # Basic project information.
    my $info = $dbh->selectrow_hashref(qq{
        SELECT strProjectReference                    AS ProjectReference,
               strComments                            AS Comments,
               intQuantity1                           AS "txtQuantity1",
               intQuantity2                           AS "txtQuantity2",
               intQuantity3                           AS "txtQuantity3",
               strStatus                              AS ProjectStatus,
               to_char(dtmRequiredDate, 'MM/DD/YYYY') AS RequiredDate,
               to_char(dtmCreationDate, 'MM/DD/YYYY') AS CreationDate
        FROM tbl_Projects WHERE lngProjectIndex = ?
    }, {}, $pid);
    @$variable{keys %$info} = values %$info;

    my %specs = eprint::service::get_specifications_pairs($log, $dbh, $pid, $sid);
    @$variable{ keys %specs } = values %specs;

    # Retrieve this services imposition information and the comparison costs
    # that went with it.
    my ($imp, $runs) =
        map { sthaw(decode_base64($_)) } @$variable{qw(imp hdnRunStyleCheck)};

    # Get the Press Type
    $variable->{PressType} = get_press_type($log, $dbh, $pid);

    $variable->{substrateType} = 'roll' if $variable->{PressType} eq 'web'
                                        or $variable->{PressType} eq 'inkjetprinter';

    # PRICE BREAKDOWN TABLES
    #
    # Figure out some pricing.
    $variable->{hdnTotalSetupCost} = $variable->{hdnPressCost} 
                                   + $variable->{hdnImpositionCharge} 
                                   + $variable->{hdnInkMixCost}  
                                   + $variable->{hdnWashUpCost} 
                                   + $variable->{hdnPlateCost} 
                                   + $variable->{hdnAqueousSetupCost} 
                                   + $variable->{hdnUVSetupCost}
                                   + $variable->{hdnSoftTouchSetupCost}
                                   + $variable->{hdnWorkTurnDryCharge};

    for my $i (1..3) {
        $variable->{"hdnTotalSetupCost$i"} 
            = $variable->{hdnTotalSetupCost} 
            + $variable->{"hdnWorkTurnDryCharge$i"};

        $variable->{"hdnPressSheetsOvers$i"} 
            = $variable->{"hdnGrossSheetCount$i"} 
            - $variable->{"hdnNetSheetCount$i"};

        $variable->{"hdnPaperDiscount$i"} 
            = $variable->{"hdnPaperTotal$i"} 
            - $variable->{"hdnPaperCost$i"};

        $variable->{"hdnStandardRunningPrice$i"} 
            = $variable->{"hdnTotalRunPrice$i"} 
            - $variable->{"hdnSpecialRunningPrice$i"} 
            - $variable->{"hdnAqueousRunningPrice$i"} 
            - $variable->{"hdnUVRunningPrice$i"}
            - $variable->{"hdnSoftTouchRunningPrice$i"}
            - $variable->{"hdnVarnishRunningPrice$i"};
    }

    @$variable{qw(hdnSheetSizeWidth hdnSheetSizeHeight)} =
        @$variable{qw(hdnSheetSizeHeight hdnSheetSizeWidth)};


    # IMPOSITION IMAGE DISPLAY (image generation handled separately)
    #
    # We don't show multipage imposition images currently. Tell the template.
    $variable->{is_multipage} = is_multipage($log, $dbh, $pid);

    # MULTI-VERSION LISTING
    #
    if ($imp and exists $imp->{layout}) {
        my $colours = gen_colours(); # Version colourizer (iterator).

        # If there's more than one version, list the versions. We don't care
        # what sheet they're on, just the version information.
        $variable->{forms} = [
            map { { versions => [ 
                      map { $_->{requested} = sprintf "%4.1f", $_->{requested};
                            $_->{final}     = sprintf "%4.1f", $_->{final};
                            $_->{over} = sprintf(
                                "%4.1f", $_->{final}-$_->{requested}
                            );
                            $_->{colour} = rgb2hex( hsv2rgb( $colours->() ));
                            $_
                          } @$_ ] }
        } @{ $imp->{layout} } ];

        # Only display if we have a m
        $variable->{forms} = undef 
            unless @{ $variable->{forms}[0]{versions} } > 1;

        # For the generation of imposition images.
        $variable->{layout} = [ map { { n => $_} } (0..$#{$imp->{layout}}) ];
    }


    # COMPARISON COST TABLE
    #
    # Runs are stored as a flat array in the following field order.
    my @fields = qw(press   run_style  plates  card      layouts  wastage 
                    width   height     gross   printing  stock    comparison  
                    cuts    width_original     height_original    chosen
					spreadcount priceperspread
    );

	return unless $runs;

	# We need to replace equipment index with strid for display.
	my $press_list = $dbh->selectall_hashref(q{
		SELECT lngindex, strID from tbl_equipment
	}, 'lngindex', {});


#print STDERR "HAVE RUNS: ", Dumper($runs);
    # Comparisons are a sorted, formatted selection of fields from each run.
    # For now we'll sort in a fixed order.
    my @comparisons =
        sort {
            $a->{press}         cmp $b->{press}         ||
            $a->{run_style}     cmp $b->{run_style}     ||
            $b->{paper}{width}  <=> $a->{paper}{width}  ||
            $b->{paper}{height} <=> $a->{paper}{height} ||
            $b->{layouts}       <=> $a->{layouts}       ||
            $b->{card}          <=> $a->{card}
        }
        map  {
            # Map the array to a hash.
            my %comp;

            @comp{ @fields } = @$_;


            # Sheet stock information.
            $comp{paper}{$_} = sprintf "%.2f", $comp{$_} for qw(width height);
            $comp{paper}{wastage} = sprintf "%5.2f", $comp{wastage};
            $comp{paper}{gross} = $comp{gross};

            # If the paper has been cut, show the original sizing.
            if ($comp{cuts}) {
                $comp{paper}{$_} = sprintf "%.2f", $comp{$_} 
                    for qw(width_original height_original);
            }

            # Pricing.
            $comp{price}{$_} = sprintf "%.2f", $comp{$_} 
                for qw(printing stock comparison priceperspread);

			$comp{press} = $press_list->{$comp{press}}{strid};

			#	$comp{price}{comparison} = $comp{priceperspread};

      #print STDERR "HAVE COMP: ", Dumper(\%comp);

            \%comp;
        }
    @$runs if @$runs;

    $variable->{comparisons} = \@comparisons;

    return OK;
}


sub display_reuse_project {
    my ($r, $log, $dbh, $variable) = @_;

    $variable->{ProjectIndex} = $r->param('ProjectIndex');

    @$variable{qw(name comments)} = $dbh->selectrow_array(q{
        SELECT strprojectreference, strcomments 
         FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $variable->{ProjectIndex});

	my $o = $dbh->selectrow_array(q{
		SELECT count(*) FROM tbl_order_contents WHERE lngprojectindex = ?
	}, undef, $variable->{ProjectIndex});

	my $q = $dbh->selectrow_array(q{
		SELECT count(*) FROM tbl_quote_details WHERE lngprojectindex = ?
	}, undef, $variable->{ProjectIndex});

	$variable->{is_ordered_or_quoted} = 1 if $o || $q;

    eprint::login::display_select_customer( $r, $log, $dbh, $variable, $variable->{cust_id} ) 
        if $variable->{is_staff};

    return OK;
}


# Copy a project (with changes supplied by the request object).
sub copy_project {
    my ($dbh, $variable, $pid, $args) = @_;

    #print STDERR "STARRT COPY PID ", Dumper(@_);

    die "Must provide a valid project ID." unless $pid;

    # NOTE: Most of this could be done within the db, or someting handling
    # generalised copying of parent and multiple child tables. Then it's just
    # a bit of changing statuses and such. What's here is just slightly
    # improved on legacy stuff.
    $dbh->begin_work;

    # Source project attributes.
    my $orig = $dbh->selectrow_hashref(q{
        SELECT strprojectreference, strcomments,   lngcustomerid,
               lngprojecttype,      lngpresstype,  strstatus,
               intquantity1,        intquantity2,  intquantity3,
               strdesign,           strprograms,   strotherprograms,
			   rfq_only, product, false as create_to_quote,  false as create_to_order,
				prod_id
        FROM tbl_projects
        WHERE lngprojectindex = ?
    }, undef, $pid);

    # Destination (new) project attributes.
    my %copy = (
        lnguserindex  => $variable->{user_id},
        lngcustomerid => $variable->{cust_id},
		copy_pid	  => $pid,
    );

    # We can change the account, name, comments, and quantity of the project.
    $copy{strprojectreference} = $args->{name}    if $args->{name};
    $copy{strcomments}         = $args->{comment} if $args->{comment};
    $copy{prod}                = $args->{prod} if $args->{prod};
    $copy{intquantity1}        = $args->{qty} if $args->{qty};
		
	#field on copy project page is named different.
    $copy{strcomments}         = $args->{comments} if $args->{comments};


    # Reset the project's status (unless the old one didn't calculate).
    $copy{strstatus} = 'Unordered' 
        unless $orig->{strstatus} eq 'uncalculated';

    my $has_new_owner = ($orig->{lngcustomerid} != $copy{lngcustomerid});

    insert(undef, $dbh, 'tbl_projects', (%$orig, %copy));
    
    # Get the next insert id in the sequence.
    my $new = $dbh->last_insert_id('', qw(public tbl_projects lngProjectIndex), {sequence=>'lngProjectIndex_seq'});

    # Copy all the services for the project (blanks shipping if new owner).
    copy_project_services($dbh, $pid, $new, $has_new_owner);

    # Copy all the assets unless told not to.
    copy_project_assets($dbh, $pid, $new) unless $args->{no_assets};

    copy_project_comments($dbh, $pid, $new);

    $dbh->commit;

print STDERR "DONE COPY PROJECT NEW PID: $new \n";

    return ($new, $has_new_owner);
}

# Copy a projects services to a destination project (for new projects only).
sub copy_project_services {
    my ($dbh, $src, $dest, $has_new_owner) = @_;

    # NOTE: This whole section should be done more in the db, no need to bring
    # the data through Perl.

    # Prepare the queries for grabbing and re-inserting specs.
    my $specs = $dbh->prepare(qq{
        SELECT strName, strValue, ui_spec
        FROM tbl_Service_Specifications
        WHERE lngProjectIndex = ?
          AND lngServiceIndex = ?
    });
    my $insert_spec = $dbh->prepare(q{
        INSERT INTO tbl_service_specifications
            (lngprojectindex, lngserviceindex, strname, strvalue, ui_spec)
        VALUES (?, ?, ?, ?, ?)
    });
	
	my $old_ship = $dbh->prepare(q{
		SELECT * FROM tbl_addresses WHERE lngindex IN 
			( SELECT shipid FROM ship_address WHERE sid = ? )
		
	});
	my $ins_ship = $dbh->prepare(q{
		INSERT INTO ship_address VALUES ( ?, ? );
	});
    my $ship_specs = $dbh->prepare(qq{
        SELECT strName, strValue, ui_spec
        FROM tbl_Service_Specifications
        WHERE lngProjectIndex = ?
          AND lngServiceIndex = ?
		  AND strname ~ ?
    });

    # Get the old project service instances. Preserve the original insertion
    # order as some horrible old code actually uses it.
    my $sth = $dbh->prepare(q{
        SELECT * FROM tbl_Project_Contents
        WHERE lngProjectIndex = ?
        ORDER BY lngServiceIndex
    });
    # Start the run through.
    $sth->execute($src);

    while (my $contents = $sth->fetchrow_hashref) {
        # Reset any status tracking states.
        $contents->{strstatus} = 'calculated' 
            unless $contents->{strstatus} eq 'uncalculated' 
                || $contents->{strstatus} eq 'error';

        $contents->{lngcompletestate} = 0;
        $contents->{lngpriority}      = 0;

       	$contents->{price_override} = undef;
        
        # Change the project ID to the new project and remove the project
        # service ID. Then insert the project service.
        $contents->{lngprojectindex} = $dest;
        my $sid = delete $contents->{lngserviceindex};

        insert(undef, $dbh, 'tbl_project_contents', %$contents);

        # Get the new service ID.
        my $new_sid = $dbh->last_insert_id('', qw(public tbl_project_contents lngserviceindex), 'ContentsServiceIndex_seq');

        # Grab the old specs.
        $specs->execute($src, $sid);
        my ($name, $value, $ui_spec);
        $specs->bind_columns( \$name, \$value, \$ui_spec );

        # Insert each spec into the new project. Ommitting a few.
        while ( $specs->fetch ) {
            next if grep{$name eq $_} qw(ServiceIndex ProjectIndex TemplateType);

            # Cripple the shipping information so it will get the address
            # for the new customer.
            next if $has_new_owner && $name =~ /(txt|ddm)Shipping/;
            next if $name =~ /(add_qty|add_price|cost_center|DueDate|accountnumber|account_number)/;

            $insert_spec->execute($dest, $new_sid, $name, $value, $ui_spec);
        }
        $insert_spec->execute($dest, $new_sid, ProjectIndex => $dest,    1);
        $insert_spec->execute($dest, $new_sid, ServiceIndex => $new_sid, 1);
		
		if ( $contents->{strservicetype} eq 'Shipping' ) {
			$old_ship->execute($sid);
    		while (my $ship = $old_ship->fetchrow_hashref) {
				my $old_id = delete $ship->{lngindex};
        		insert(undef, $dbh, 'tbl_addresses', %$ship);

        		# Get the new address ID.
        		my $new_id = $dbh->last_insert_id(
            		'', qw(public tbl_addresses lngindex));

				$ins_ship->execute($new_sid, $new_id);
				$ship_specs->execute($src, $sid, $old_id);

				my ( $n, $v, $u );
				$ship_specs->bind_columns( \$n, \$v, \$u );
				while ( $ship_specs->fetch ) {		
            		next if $n =~ /(accountnumber|account_number)/;
					#Seperate spec name from old index.
					$n =~ /(\w+)-(\d+)$/;
            		if ( $1 && $2 ) {
						# Insert spec with new address index.
						$insert_spec->execute(
							$dest, $new_sid, "$1-$new_id", $v, $u);
					}
				}
				
			}
			
			
		}
    }

    return 1;
}

sub copy_project_comments {
    my ($dbh, $src, $dest) = @_;

    my $files = $dbh->prepare(q{
        SELECT *  FROM project_comments WHERE pid = ?
    });

    my $insert = $dbh->prepare(q{
        INSERT INTO project_comments VALUES (?, ?, ?, ?, ?)
    });

    # Copy the file metadata in the DB from source to dest.
    $files->execute($src);
    my ($pid, $user, $assigned, $date, $comment);
    $files->bind_columns(\$pid, \$user, \$assigned, \$date, \$comment);

    $insert->execute($dest, $user, $assigned, $date, $comment)
        while $files->fetch;


    return;
}


# Copy the project files (and file metadata in DB) to the destination pid. All
# approvals are cleared from the files.
sub copy_project_assets {
    my ($dbh, $src, $dest) = @_;

    my $files = $dbh->prepare(q{
        SELECT filename, description, owner FROM project_files WHERE pid = ?
    });

    my $insert = $dbh->prepare(q{
        INSERT INTO project_files (pid, filename, description, owner)
        VALUES (?, ?, ?, ?)
    });

    # Copy the file metadata in the DB from source to dest.
    $files->execute($src);
    my ($filename, $description, $owner);
    $files->bind_columns(\$filename, \$description, \$owner);

    $insert->execute($dest, $filename, $description, $owner)
        while $files->fetch;

    # Copy the files themselves.
    require File::Copy::Recursive;
    my $count = File::Copy::Recursive::dircopy(
        get_path(undef, $dbh, $src),
        get_path(undef, $dbh, $dest),
    );

    return $count;
}


# Adds a cutstom line item.
sub insert_custom_service {
    my ( $log, $dbh, $pid, $desc, $docket, @prices ) = @_;

    sql::insert( $log, $dbh, 'tbl_Project_Contents',
        lngProjectIndex => $pid,
        strStatus       => 'calculated',
        strServiceType  => 'Custom'
    );
    # Get the just inserted service index from the project contents.
    my $sid = $dbh->selectrow_array(q{
        SELECT currval('ContentsServiceIndex_seq')
    });

    # Insert service type and display name.
    sql::insert( $log, $dbh, 'tbl_Service_Specifications',
        lngProjectIndex => $pid,
        lngServiceIndex => $sid,
        strName         => 'ServiceType',
        strValue        => 'Custom' );
    sql::insert( $log, $dbh, 'tbl_Service_Specifications',
        lngProjectIndex => $pid,
        lngServiceIndex => $sid,
        strName         => 'ServiceName',
        strValue        => $desc );

    sql::insert( $log, $dbh, 'tbl_Service_Specifications',
        lngProjectIndex => $pid,
        lngServiceIndex => $sid,
        strName         => 'hide_docket',
        strValue        => $docket ); 

    # Insert pricing.
    for my $i (1..3) {
        my $price = $prices[$i-1] || '0.00';

        sql::insert( $log, $dbh, 'tbl_Service_Specifications',
            lngProjectIndex => $pid,
            lngServiceIndex => $sid,
            strName         => "txtPrice$i",
            strValue        => $price
        );
    }

    return 1;
}





use constant BUILD_PAGE    => '/build';
use constant VIEW_PAGE     => '/main/proj/proj_view.html';
use constant TEMPLATE_PAGE => '/template/record.html';

# Instead of the mass of if/elses that was the project view function, we'll
# use a simple dispatch table for the moment.
{
    my %DISPATCH = (
        create            => \&create_project,
        create_multiple   => \&create_multiple,
        create_checkout   => \&inventory_checkout,
        edit              => \&edit_project,
        copy              => \&copy,
		add_qty           => \&add_qty,
        change_order     =>   \&change_order,
        complete_change_order => \&complete_change_order,
        reorder           => \&reorder,
        make_predefined   => \&make_predefined,
		update_order	  => \&update_order,

        remove            => \&remove_item,   # Remove a service

        add_line_item          => \&add_line_item,         # Add a custom line item
        edit_line_item         => \&edit_line_item,         # Add a custom line item
        add_discount           => \&add_discount,          # Create fixed price project
        add_per_item_discount  => \&add_per_item_discount, # Create fixed price project
		complete	       => \&complete_project,
		add_product_to_order   => \&add_product_to_order,
		update_product		=> \&update_product,
    );

    sub dispatch {
        my ($r, $log, $dbh, $cookie, $variable) = @_;

        my $action = $r->param('action') or die "No action given to dispatch";
        my $func   = $DISPATCH{$action}  or die "Invalid action ($action)";

print STDERR "START DISPATCH: COOKIE: $cookie ACTION: $action FUNC: $func \n";

        # Project ID is required for everything but creation.
        my $pid;
        if ($action !~ /^create/ && $action !~ /^add_product/) {
            $pid = $r->param('pid');
            $pid =~ tr/0-9//cd;

            die "No or invalid project ID"           unless $pid;

            my $allowed = project_allowed($dbh, $pid, $variable);

            die "Project doesn't exist"              unless defined $allowed;
            die "No permission to edit project $pid" unless $allowed;
        }
        
        return $func->(@_, $pid);
    }
}


sub update_product {
	my ($r, $log, $dbh, $cookie, $var, $pid) = @_;

	my $prod = $dbh->selectrow_array(q{SELECT prod FROM tbl_projects WHERE lngprojectindex = ?}, undef, $pid);
	die("Missing Product") unless $prod;

	my $dsc = $dbh->selectrow_array(q{SELECT strcomments From tbl_projects WHERE lngprojectindex = ? }, undef, $pid);

	my @a = split('\*\*', $dsc);

	if ( scalar @a == 3 ) {
		$dbh->do(q{ Update tbl_projects set strcomments = ? where lngprojectindex = ?}, undef, $a[2], $pid); 
	}

	$dbh->do(q{ Update tbl_products set project = ?, description = NULL where id = ?}, undef, $pid, $prod); 

	return "/main/proj/proj_view.html?pid=$pid";

}



sub add_product_to_order {
	my ($r, $log, $dbh, $cookie, $var, $pid) = @_;


	
	my $product = $r->param('product');
	my $qty     = $r->param('txtQuantity1') ||  1;
	my $jobname = $r->param('jobname') ||  undef;
    my $addprice = $r->param('addprice') || 0;
	my $versions = $r->param('versions1') ||  1;

	$jobname .= " $versions Versions " if $versions > 1;
print STDERR "PRODUCT: $jobname \n";

	die("Invalid request. Product can not be added to order") unless $product && $qty;

    # Add new parameter to the list
	my $order_id = eprint::order::add_product_to_order($cookie, $var, $product, $qty, undef, $jobname, $versions, $addprice);
	
	$ENV{HTTP_REFERER} =~ /.*(\/main\/ecommerce.*)/;
	my $ref = $1;
	
	#die("have ref: $ref -- $1 ");
	return "$ref";

}

sub change_order {
  my ($r, $log, $dbh, $cookie, $var, $pid) = @_;
  my ($destination, $new, $status);
  if ($r->param('proj_specs') eq 'proj_specs_yes') {
    #a copy of the project must be made
    $destination = copy(@_);
    ($new) = $destination =~ m/pid=(\d+)$/;
    ($status) = eprint::project::project_status($dbh, $pid);
    #cancel the old project
    my $sth = $dbh->prepare("update tbl_projects set strstatus = ? where lngprojectindex = ?");
    $sth->execute('Cancelled', $pid);
    $sth->execute($status, $new);
  }

  #register the change order
  PQS::model::change_order::create_change_order($pid, $new, $r->param('change_order'));
  return complete_change_order(@_) if ($r->param('proj_specs') eq 'proj_specs_no');

  return $destination;
}

sub complete_change_order {
  my ($r, $log, $dbh, $cookie, $var, $pid) = @_;
  PQS::model::change_order::complete_change_order($pid);
  my $change_order = PQS::model::change_order::get_change_order($pid);

  my $order = PQS::model::order::get_order_by_pid($pid);

  #change order pid
  if ($change_order->{pid_to}) {
    my $content = PQS::model::order::get_ordered_project_info($pid);
    die "Ordered project information was not found" unless (%$content);
    PQS::model::order::remove_project($order->{lngorderid}, $pid);
    eprint::order::add_project_to_order($log, $dbh, $cookie, $var, $change_order->{pid_to}, $order->{lngorderid});
    $content->{lngprojectindex} = $change_order->{pid_to};
    PQS::model::order::save_ordered_project_info($content);
  }

  #send email
  eprint::order::send_sales_order($r, $log, $dbh, $order->{lngorderid}, 1);

  return "/main/proj/proj_view.html?pid=" . ($change_order->{pid_to} ? $change_order->{pid_to} : $pid);
}

sub complete_project {
    my ($r, $log, $dbh, $cookie, $var, $pid) = @_;

	require eprint::employee_project;
    eprint::employee_project::complete_project( $r, $dbh, $pid, $var);

	return "/main/proj/proj_view.html?pid=$pid";


}

sub update_order {
    my ($r, $log, $dbh, $cookie, $var, $pid) = @_;
print STDERR "UPDATE MY ORDER - $cookie - $pid \n";
	eprint::order::update_order($r, $log, $dbh, $cookie, $var, $pid);
	return "/main/proj/proj_view.html?pid=$pid";
	

}

sub make_quote {
    my ($r, $log, $dbh, $cookie, $var, $pid) = @_;
print STDERR "CREATE MY PROJECT TO QUOTE - $cookie - $pid \n";

		my $cust_id = $var->{'cust_id'};
		my $user_id = $var->{'user_id'};

		$dbh->do(qq{
			UPDATE tbl_projects set create_to_quote = true WHERE lngprojectindex = $pid 
		});
		my $quote_id = eprint::quote::add_project_to_quote( 
						$r, $log, $dbh, $cust_id, $user_id, $cookie, undef, $pid );
}

sub make_order {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;
		my $user_id = $variable->{user}{id};
		$dbh->do(qq{
			UPDATE tbl_projects set create_to_order = true WHERE lngprojectindex = $pid 
		});
		my ($order_id, $error) = eprint::order::add_project_to_order(
           	$log, $dbh, $cookie, $variable, $pid
		);

	   	return misc::error($log, $dbh, $variable, 'Error', $error) if $error;
}


sub reorder {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

	my  $pid = $r->param('pid');


print STDERR "RE ORDER PID: $pid \n";
	($pid) = copy_project($dbh, $variable, $pid, {});
print STDERR "RE ORDER NEW PID: $pid \n";

	make_order($r, $log, $dbh, $cookie, $variable, $pid);
	
    return BUILD_PAGE . "?pid=$pid;level=0";

}

# Create a dummy project to upload files.
sub dummy_project {
    my ($r, $log, $dbh, $cookie, $variable) = @_;

	my $prod = $dbh->selectrow_array(q{
		SELECT lngprojectindex FROM tbl_projects
		WHERE strprojectreference = 'Dummy Project'
		LIMIT 1
	});

	my $pid_str = create_project($r, $log, $dbh, $cookie, $variable, [1], $prod, 'Dummy Project');

	$pid_str =~ /pid\=(\d*)/;
	my $pid = $1;

	$dbh->do(q{
		UPDATE tbl_projects SET cookie = ? where lngprojectindex = ?
	}, undef, $cookie, $pid);

print STDERR "HAVE $pid FROM STRING: $pid_str COOKIE: $cookie \n";
	return $pid;
}

# Create the project and start the build process.
sub create_multiple {
    my ($r, $log, $dbh, $cookie, $var) = @_;

	my $page; 

	foreach my $field ($r->param()) {

		next unless $r->param($field) && $field =~ /txtQuantity1_(\d*)/;

		my $id = $1;
		print STDERR "HAVE ID: $id - $1 \n";

		my $qty  = $r->param("txtQuantity1_$id");
		my $prod = $r->param("predefined_$id");
		my $name = $r->param("txtProjectReference_$id");
		my $inv  = $r->param("inventory_$id");
		
		die("Product Broken Name: $name PROD: $prod QTY: $qty ") unless $qty && $prod && $name;

		my $qtys = [$qty];

		$page = create_project($r, $log, $dbh, $cookie, $var, $qtys, $prod, $name);

		my $pid = $var->{new_pid};

		$dbh->do(q{
			UPDATE tbl_projects SET inv_not = ?  WHERE lngprojectindex = ?
		}, undef, $inv, $pid) if $inv;



	}

	return $page;


}

# Create the project and start the build process.
sub create_project {
  my ($r, $log, $dbh, $cookie, $variable, $qty, $predefined, $projref) = @_;

  map { $qty->[$_-1] = int $qty->[$_-1] || $r->param("txtQuantity$_") || 0 } 1..3;
map { print STDERR "HAVE PARAM: $_ = " . $r->param($_) } $r->param();

  $projref ||= $r->param('txtProjectReference');
  die('Missing Project Referenece') unless $projref;

  my $pid;

  $predefined ||= $r->param('predefined');

  print STDERR "START CREATE PROJECT \n";

  if ($predefined) {
    $variable->{user_id} = $r->param('ddmUser') if $r->param('ddmUser');
    $pid = create_project_from_predefined($r, $log, $dbh, $cookie, $variable, $qty, $predefined, $projref);

    modify_services($r, $log, $dbh, $cookie, $variable, $pid);
    print STDERR "CREATE MY PROJECT TO ORDER - $cookie - $pid \n";
		my $i = $r->param('item') || $predefined;

		$dbh->do('UPDATE tbl_projects SET prod_id = ? WHERE lngprojectindex=?', undef, $i, $pid);

		if ( $r->param('create_to_order') ) {
			$dbh->do('UPDATE tbl_projects SET create_to_order = true WHERE lngprojectindex = ?', undef, $pid);
			make_order($r, $log, $dbh, $cookie, $variable, $pid);
		}

# Make all predefined projects  go to order;
		if ( $r->param('MakeOrder') ) {
			make_order($r, $log, $dbh, $cookie, $variable, $pid);
		} elsif ( $r->param('MakeQuote') ) {
			make_quote($r, $log, $dbh, $cookie, $variable, $pid);
		}

		$variable->{new_pid} = $pid;
  } else {
    #print STDERR "CREATE PROCESS ", Dumper(@_);
$pid = create_process($r, $log, $dbh, $cookie, $variable, $qty, $predefined, $projref);
    }

    $dbh->do(q{
      UPDATE tbl_projects SET create_to_order = true WHERE lngprojectindex = ?
      }, undef, $pid) if $r->param('create_to_order');

    #Special param used for domino's mailing projects.
    if ( $r->param('mail_type') ) {
      my $type = $r->param('mail_type');
      my $art  = $r->param('mail_art');

      die("MISSING MAIL ART FOR MAIL TYPE: $type ") unless $art;

      $dbh->do(q{
        UPDATE tbl_projects SET mail_type = ?, mail_art  = ? 
        WHERE lngprojectindex = ?
        }, undef, $type, $art, $pid);

    }




    die "Couldn't create project" unless $pid;

    my $x = has_pdf_template(undef, $dbh, $pid);
    print STDERR " 1 CREATE PROJECT 2 X: $x T: " . $r->param('template') . " \n\n";

    # If we're creating a project with PDF template, (and one isn't already
    # associated with it (can happen with predefined projects), create the
    # project and it's dir but belay the calculation until after filling.
    if ($r->param('template') ) {
      #if ($r->param('template') && ! has_pdf_template(undef, $dbh, $pid)) {

      print STDERR "TIME TO INIT TEMPLATE PROJECT \n\n";
      require eprint::Template;

      # Copy the template into the project dir and create it's database.
      eprint::Template::init_template($dbh, $pid, $r->param('template'));
    }
    if ( $r->param('mail_type') ) {

      eprint::mailing::reserve_mail($r, $dbh, $variable, 
        $pid, $r->param('txtQuantity1'));

      eprint::mailing::make_address_file($r, $dbh, $variable, $pid);
    }

    my $p  = "pid=$pid";
    $p .= ";level=0"           if $predefined;
    $p .= ";create_to_order=1" if $r->param('create_to_order');

    return (has_pdf_template(undef, $dbh, $pid) ? TEMPLATE_PAGE : BUILD_PAGE) 
    . "?$p";
  }

sub inventory_checkout {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    my $qty = int($r->param('CheckOutQty')) 
        or die "Invalid checkout quantity";
    
    $pid = eprint::inventory::make_checkout_project( 
                    $r, $log, $dbh, $cookie, $variable );

	my $p = "pid=$pid";
       $p .= ";create_to_order=1" if $r->param('create_to_order');
    return BUILD_PAGE . "?$p";
}


sub edit_project {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    my $modified = edit_process(@_);

    # Send for a full recalculate if the quantities have changed. Otherwise
    # the build process will just pickup any added services.

    my $p = $r->param('create_to_order') ? ";create_to_order=1" : ''; 

	$modified = 2;
print STDERR "EDIT: $modified, $p \n\n";
    return $modified 
        ? BUILD_PAGE . "?pid=$pid" . ($modified > 1 ? ';level=0' : '') . $p
        : VIEW_PAGE  . "?pid=$pid" . $p;
}

sub copy {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    # Change the customer the new project will be owned by (if specified by an
    # admin). If done the project will be recalculated later on.
    if (   $r->param('ddmCustomer') 
         && grep { $variable->{user_type} eq $_ } qw(A E))
    {
        eprint::login::select_customer( $r, $log, $dbh, $cookie, $variable );
    }
    my ($new, $changed);
	if ( $r->param('move_project') ) {

		my $old = get_path(undef, $dbh, $pid);

		$dbh->do(q{
			UPDATE tbl_projects SET lngcustomerid = ? WHERE lngprojectindex = ?
		}, undef, $r->param('ddmCustomer'), $pid);
		$new = $pid;
		$changed = 1;

		my $new = get_path(undef, $dbh, $pid);

		# Copy the files themselves.
		require File::Copy::Recursive;
		my $count = File::Copy::Recursive::dircopy($old, $new);
		

	} else {
		($new, $changed) = copy_project($dbh, $variable, $pid, {
			name      => ($r->param('name')    || ''),
			comments   => ($r->param('comments') || ''),
			no_assets => !$r->param('copy_assets'),
		});
	}

    # TODO Fix SignatureIndex issue (bug 3675) so we don't have to force a
    # recalculation.
    $changed = 1;

    my $p  = "pid=$new";
       $p .= ";level=0"           if $r->param('predefined');
       $p .= ";create_to_order=1" if $r->param('create_to_order');

       #return (has_pdf_template(undef, $dbh, $pid) ? TEMPLATE_PAGE : BUILD_PAGE) 
       #  . "?$p";

    # Recalculate the project if the customer has changed.
    # Force recalc to make sure price override is reset after copy.
    return $changed ? BUILD_PAGE . "?pid=$new;level=0"
                    : VIEW_PAGE  . "?pid=$new";
}

# Mark the project as predefined.
sub make_predefined {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    my $status = $dbh->selectrow_array(q{
        SELECT strstatus FROM tbl_projects WHERE lngprojectindex = ?
    }, undef, $pid);

    $dbh->do(q{
        UPDATE tbl_projects SET strstatus = 'predefined' 
        WHERE lngprojectindex = ?
    }, undef, $pid) if $status eq 'Unordered';

    return VIEW_PAGE . "?pid=$pid";
}

# Remove the given service from the project.
sub remove_item {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    my $sid = $r->param('sid') or die "Invalid service ID";

    # We're modifying the project (should be a DB trigger)
    sql::update( $log, $dbh, 'tbl_Projects', "lngProjectIndex = $pid",
        dtmLastModified => 'NOW()', 
    );

    remove_service($log, $dbh, $pid, $sid);

    # See if we need to recalculate anything.
    return BUILD_PAGE . "?pid=$pid";
}

# Add a custom line item to the given project.
sub edit_line_item {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

	my $edit = $r->param('edit');
	my $sid = $r->param('sid');
	my $name = $r->param('name');
	my $price = $r->param('price');
	my $docket = $r->param('docket');
	my $hide_docket = $r->param('hide_docket');
	my $have_price = 0;

	map { $have_price = 1 if $_ eq 'price' } $r->param();

	print STDERR "HAVE PRICE: $have_price , PRice: $price \n";

	if ( $r->param('edit_service') ) {
		#Display input for selected service unless we are saving price
		$edit =  $r->param('edit_service') unless $have_price;

		#if saving price field but it is empty, reset price override.
		if ( ($have_price &&  $price eq '') || $r->param('reset') ) {
			print STDERR "RESET PRICE OVERRIDE: $sid \n";

			$dbh->do(q{UPDATE tbl_project_contents set price_override = NULL where lngserviceindex = ?}, 
				undef, $sid);

			my $log = session::log;
			eprint::Build::build($log, $dbh, $pid, $variable, 0);
		}
	};

	$price = int($price * 100) / 100;

	my $data = {}; 
	$data->{txtPrice1} = $price if $price;
	$data->{ServiceName} = $name if $name;
	$data->{docket} = $docket if $docket;
	$data->{hide_docket} = $hide_docket if $hide_docket;


	if ( $sid ) {
    	insert_service_specs($log, $dbh, $pid, $sid, %$data);
	}

	if ( $price || $price eq '0' ) {
		$dbh->do(q{UPDATE tbl_project_contents set price_override = ? where lngserviceindex = ?}, 
			undef, $price, $sid);
	}

	map { print STDERR "HAVE PARAM: $_  = " . $r->param($_) . "\n"; } $r->param();



  #print STDERR "HAVE EDIT LNIE", Dumper($edit, $name, $price, $sid, $edit);


	#return BUILD_PAGE . "?pid=$pid;edit=11111";
	#
    return "/main/proj/proj_view.html?pid=$pid;edit=$edit";
}


# Add a custom line item to the given project.
sub add_line_item {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    my $name   = $r->param('item_name');
	my $docket = $r->param('hide_docket'); 
    my @prices = map { $r->param("price-$_") || 0 } 1..3;

# Very basic garbage removal.
# Allow negative numbers, remove commas and other crap.
	map { 
		$_ =~ s/\,//g;
		$_ =~ /(\-?\d+\.?\d*)/; $_ = $1; 
	} @prices;

    insert_custom_service($log, $dbh, $pid, $name, $docket, @prices)
        if @prices;

    return VIEW_PAGE . "?pid=$pid";
}

# Add a discount item (which makes the project fixed price).
sub add_discount {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    # If we're not already a fixed price project add the discount service.
    if (!is_fixed_price($dbh, $pid)) {
        insert_service($log, $dbh, $pid, 'Discount', {
                                user_requested => 1,
                                need_level     => 0,
        });
    }

    return BUILD_PAGE . "?pid=$pid";
}

# Add a per item discount (which makes the project have a fixed unit price).
sub add_per_item_discount {
    my ($r, $log, $dbh, $cookie, $variable, $pid) = @_;

    # If we're not already a fixed price project add the discount service.
    if (!is_fixed_price($dbh, $pid)) {
        insert_service($log, $dbh, $pid, 'PerItem', {
                                user_requested => 1,
                                need_level     => 0,
        });
    }

    return BUILD_PAGE . "?pid=$pid";
}
sub project_notification {
	my ($r, $dbh, $var) = @_;
	
	my $log = $r->log;
	my $id = $r->param('id');

#	print STDERR "NOT PARAMS", Dumper($r->param()) . "\n";
#	print STDERR "VAR PARAMS", Dumper($var, $id) . "\n";


	my $data = $dbh->selectrow_hashref(q{
		SELECT strfirstname, strlastname, stremail, u.strphone , strcompanyname 
		FROM tbl_customer_users u, tbl_customer c WHERE 
		u.lngcustomerid = c.lngcustomerid AND lnguserid = ?
	}, undef, $var->{user_id});

	my $info;
	if ( $r->param('pid' ) ) {
		$dbh->do(q{
			DELETE FROM tbl_order_contents WHERE lngprojectindex = ?
		}, undef, $r->param('pid'));
		$dbh->do(q{
			DELETE FROM tbl_quote_details WHERE lngprojectindex = ?
		}, undef, $r->param('pid'));


		$info = $dbh->selectall_arrayref(q{
			SELECT name, value FROM hybird_specs WHERE pid = ?
		},{Slice=>{}}, $r->param('pid'));

		$data->{error_code} = '1101-UC';
		$data->{pid} = $r->param('pid');
	} elsif( $r->param('id') ) { 
	# Could not match Predifined project from hybrid page.

		$data->{pid} = dummy_project($r, $r->log, $dbh, $var->{cookie}, $var);

		$info = $dbh->selectall_arrayref(q{
			SELECT name, value FROM hybird_specs WHERE req = ?
		},{Slice=>{}}, $r->param('id'));

		$data->{error_code} = '1102-NMF';
	} else {
		print STDERR "HAVE NO PID OR ID FROM PROJECT NOTIFICATION";
	}

	map { $data->{$_->{name}} = $_->{value} } @{$info};

	$data->{item} = $dbh->selectrow_array(q{
		SELECT name FROM product.item WHERE id = ?
	}, undef, $data->{item});

	$data->{ddmUser} = $dbh->selectrow_array(q{
		SELECT strfirstname || ' ' || strlastname FROM tbl_customer_users WHERE lnguserid = ?
	}, undef, $data->{ddmUser}) if $data->{ddmUser};

#print STDERR "NOT INFO", Dumper($data);

    $data->{siteURL} = configuration::get_value( $log, $dbh, 'siteURL' );

  my $debug = Dumper($data);
	$data->{debug} = $debug;
	$data->{debug} =~ s/\n/<br>/g;


  #print STDERR " NOT DUMPER " , Dumper($data->{pid}, $var->{cookie});
	my $file = misc::load_file($r, q{/email/forms/project_requires_special_attention.html});

	$file = ssi::variable_substitution($r, $log, $dbh, $file, $data);

	my $email = $dbh->selectrow_array(q{
		select notificationemail from tbl_customer where strcompanyname = 'SAFEWAY';
	});

#************** TESTING ONLY ***************
#$email = 'wcober@print-quotes-software.com' if $variable->{user_id} == 2;
#*******************************************
    my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => $email,
         TO      => $email,
         SUBJECT => "New Project Request"
    );
print STDERR "SENT PROJECT  NOTICE TO: $email \n";

#	misc::email_with_template($r, $log, $dbh, $file, \%mail, $info);
	misc::send_email_with_attachment(
        $r, $log, \%mail, '', encode_qp($file), 'text/html',
         'quoted-printable'
    );

	return;

}

sub add_qty {
    my ($r, $log, $dbh, $cookie, $var, $pid, $qtys, $press_type) = @_;

    my ($new, $changed) = copy_project($dbh, $var, $pid, {
        name      => ($r->param('name')    || ''),
        comments   => ($r->param('comments') || ''),
        no_assets => !$r->param('copy_assets'),
    });

	$dbh->do(q{
		UPDATE tbl_projects SET eid = ( 
			SELECT eid FROM tbl_projects WHERE lngprojectindex = ? 
		) WHERE lngprojectindex = ?
	},undef, $pid, $new);

	$dbh->do(q{
		UPDATE tbl_projects SET lngpresstype = ?  WHERE lngprojectindex = ?
	},undef, $press_type, $new) if $press_type;

	my $old_q1 = $dbh->selectrow_array(q{
		SELECT intquantity1 FROM tbl_projects 
		WHERE  lngprojectindex = ?
	}, undef, $pid);
print STDERR "Q1: PID: $pid \n ";

	$pid = $new;

	edit_process($r, $log, $dbh, $cookie, $var, $pid, 1, $qtys);

	my $new_q1 = $dbh->selectrow_array(q{
		SELECT intquantity1 FROM tbl_projects 
		WHERE  lngprojectindex = ?
	}, undef, $pid);

	my $mv = $dbh->selectrow_array(q{
		SELECT strvalue FROM tbl_service_specifications
		WHERE  lngprojectindex = ? AND strname = 'version_quantities'
	}, undef, $pid);

	my @data = split /,/,$mv;
	my $new_mv;
	my $count;
	while (@data) {
		my $name = shift @data;
		my $qty  = shift @data;
		my $new_qty = int(($qty / $old_q1) * $new_q1);
		$new_mv .= scalar @data < 2 ? "$name,$new_qty" : "$name,$new_qty,";
		$count += $new_qty;
	}
	$count = $new_q1 - $count;

	@data = split /,/,$new_mv;
	$new_mv = '';
	while (@data) {
		my $name = shift @data;
		my $qty  = shift @data;
		$qty++ if $count > 0;
		$count--;
		$new_mv .= scalar @data < 2 ? "$name,$qty" : "$name,$qty,";

	}

	$dbh->do(q{
	    UPDATE tbl_service_specifications SET strvalue = $1
	    WHERE lngprojectindex = $2 AND strname = 'version_quantities'
	},undef,$new_mv,$pid);

	$dbh->do(q{
	    DELETE FROM tbl_service_specifications
	    WHERE lngprojectindex = $1 AND strname ~ 'override'
	},undef,$pid);

	$dbh->do(q{
	    DELETE FROM tbl_service_specifications
	    WHERE lngprojectindex = $1 AND strname = 'press'
	},undef,$pid);

	

	eprint::Build::build($log, $dbh, $pid, $var, 0);

    # Recalculate the project if the customer has changed.
    return '/main/proj/proj_hist.html';

}


1;
