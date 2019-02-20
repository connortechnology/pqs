package eprint::Template;
use strict;
use warnings;

use Apache2::Const qw(OK HTTP_MOVED_TEMPORARILY);
use Apache2::RequestUtil ();
use Data::Dumper;
use Text::CSV_XS 0.45;

use PQS::Template;
use eprint::project qw(get_path);

use constant OVERVIEW_PAGE => '/template/main.html';
use constant ASSET_PAGE    => '/template/assets.html';

use base qw(Exporter);
our @EXPORT_OK = qw(get_datasource);

use File::Copy qw(cp);
use File::Path qw(mkpath);

#cust_id  1  - PQS
#cust_id  12 - Print Pak
#cust_id  15 - Impact

use constant  MULTI => qw( 1 12 15 10283 113 147 );

sub init_template {
    my ($dbh, $pid, $template_id) = @_;

print STDERR "********* INIT TEMPLATE PID: $pid Template: $template_id  ****************** \n\n";
    my $proj_dir = get_path(undef, $dbh, $pid);

    # Create a template dir.
    mkpath("$proj_dir/.template")
        or die "Couldn't create template dir for project ($pid)."
		unless -e "$proj_dir/.template";

	$dbh->do(qq{UPDATE tbl_projects SET pdf_template = '$template_id' WHERE lngprojectindex = $pid});
	$dbh->commit;

    # Get the source template location and create a copy in the project dir.
    my $source = $dbh->selectrow_array(q{
        SELECT filename FROM template.template WHERE id = ?
    }, undef, $template_id);

    my $template_path = "$proj_dir/.template/template.pdf";

    cp($source, $template_path)
        or die "Couldn't copy PDF template into project dir ($pid) from : $source - $template_path.";

    # Create the template database file and populate it's tables.
    my $template_dbh = get_datasource($dbh, $pid);

    # Get the fields from the template and create a data table from them.
    my $info = PQS::Template::get_pdf_info($template_path);

    my @fields = sort {   $a->{page} <=> $b->{page} 
                       || $a->{Custom}{order} <=> $b->{Custom}{order}
                      }
                     @{ $info->{blocks} };

    my $fields = join ', ', map { $dbh->quote_identifier($_->{Name}) . ' TEXT' } @fields;

    # Create a meta-data table of the fields and their types.
    $template_dbh->do("CREATE TABLE template_id (id TEXT)");
    my $temp_id = $template_dbh->prepare('INSERT INTO template_id VALUES (?)');
	$temp_id->execute($template_id);


    $template_dbh->do("CREATE TABLE data (id INTEGER PRIMARY KEY, $fields)");

    # Create a meta-data table of the fields and their types.
    $template_dbh->do("CREATE TABLE field (name TEXT, label TEXT, type TEXT)");

    my $insert = $template_dbh->prepare('INSERT INTO field VALUES (?, ?, ?)');
    
    for my $field (@fields) {
        my $type = lc $field->{Subtype};
        
        $insert->execute(
            $field->{Name}, 
            $field->{Description} || $field->{Name}, 
            $type
        );

        # Create a table and directory for each asset (pdf/image fields).
        if ($type ne 'text') {
            my $table = $dbh->quote_identifier("asset_$field->{Name}");

            $template_dbh->do(qq{
                CREATE TABLE $table (id INTEGER PRIMARY KEY, name TEXT UNIQUE)
            });        

            mkpath("$proj_dir/.template/assets/$field->{Name}")
                or die "Couldn't create asset dir ($field->{Name}) for project ($pid).";

        }
    }

    # Show asset names instead of IDs for data views.
    create_export_view($template_dbh, \@fields);

    $template_dbh->commit;

    return 1;
}

# Create an view so assets show as their names instead of their IDs. Used for
# export to file so it's prettier for the user.
sub create_export_view {
    my ($dbh, $fields) = @_;

    my (@view_fields, @asset_tables, @joins);
    for my $field (@$fields) {
        my ($table, $name);

        if ($field->{Subtype} eq 'Text') {
            $table = 'data';
            $name  = $dbh->quote_identifier($field->{Name});
        }
        else {
            $table = $dbh->quote_identifier("asset_$field->{Name}");
            $name  = $dbh->quote_identifier('name');

            my $join = 'data.' . $dbh->quote_identifier($field->{Name}) 
                     . " = $table.id";

            push @asset_tables, "LEFT JOIN $table ON ($join)";
        }

        my $label = $dbh->quote_identifier(
            $field->{Description} || $field->{Name}
        );

        push @view_fields, "$table.$name AS $label";
    }

    my $view_fields = join ', ', @view_fields;
    my $tables      = join ' ', ('data', @asset_tables);

    $dbh->do(qq{
        CREATE VIEW export AS
            SELECT data.id AS "ID", $view_fields
            FROM $tables
    });

    return 1;
}



# Get a DBI connection to the project's template datasource.
sub get_datasource {
    my ($dbh, $pid) = @_;

    my $path = get_path(undef, $dbh, $pid)
        or die "Can't find project files.";

    return DBI->connect(
        "dbi:SQLite:dbname=$path/.template/template.db", '', '', 
        {
            AutoCommit => 0,
            RaiseError => 1,
        }
    ) or die DBI->errstr;
}

# Get the project id from the apache request object.
sub get_pid {
    my $r = shift;

    my $pid = $r->param('pid');
       $pid =~ tr/0-9//cd;

    die "Invalid project ID" unless $pid;

    return $pid;
}

# Extract all pertinent info from the PDF (block structure, size, etc.)
sub get_template_info {
    my ($dbh, $pid) = @_;

    my $path = get_path(undef, $dbh, $pid)
        or die "Can't find project files.";

    return PQS::Template::get_pdf_info("$path/.template/template.pdf");
}

# MAIN DISPLAY/OVERVIEW
#

# Display an overview of the currently selected project's template and data.
sub overview {
    my ($r, $dbh, $variable) = @_;

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);
	my $x = $r->method;
	my $y = $r->param('Finish');

print STDERR "START OVERVIEW X: $x Y: $y \n";

	# Post From Record page.
    if ($r->method eq 'POST' and $r->param('Finish') ) {
print STDERR "CHANGE RECORD OVERVIEW \n";
        change_record($r, $datasource, $dbh, $variable->{cust_id}); 
    }
    my $info       = get_template_info($dbh, $pid);

	# Post From Record page.
    if ($r->method eq 'POST' and $r->param('Finish') ) {
        change_record($r, $datasource, $dbh, $variable->{cust_id}); 
    }

#    my $sth = $datasource->prepare(q{SELECT * FROM export});
#    $sth->execute;
my $sth;

	my $data = $datasource->selectall_arrayref(q{
		SELECT * from data
	}, {Slice =>{}});
	my $record = @{$data}[0];
	map {
		$variable->{record_link} .=";$_=" . $record->{$_} if $record->{$_};
	} keys %{$record};

	$variable->{pages} = $info->{pages};

    # Get the field headings.
    $variable->{headers} = [ map { { name => $_ } } @{ $sth->{NAME} } ];
    $variable->{head} = [ map { { name => $_ } } @{ $sth->{ID} } ];

use Encode;
use HTML::Entities;
use Apache2::Util;

    # Get tabular data for generating an HTML table (massaged for our enimic
    # templating "system").
	my $n = $datasource->selectrow_array(q{
		SELECT count(*) from DATA
	});

#	my @tmp_data;
#	for my $x ( 1..3) {
#		push  @tmp_data, [$x];
#	}
#    $variable->{data} = [ 
#        map { { fields => [ map { {datum => $_} } @$_ ] } } 
#		@tmp_data
##@{ $sth->fetchall_arrayref } 
#    ];
	$variable->{data} = $data;


    map { 
	 map { $_->{datum} = decode_utf8($_->{datum}); $_->{datum} =~ s/\x{e2}\x{80}\x{a2}/&bull;/; } @{$_->{fields}}; 
	 map { $_->{datum} =~ s/\x{fffd}/&bull;/; } @{$_->{fields}}; 

	} @{$variable->{data}}; 



    $variable->{count}           = $n;
    $variable->{pid}             = $pid;
    $variable->{create_to_order} = $r->param('create_to_order') 
        if $r->param('create_to_order');
	
	if ( $r->param('go') ) {
		$r->status(HTTP_MOVED_TEMPORARILY);
		$r->headers_out->set(Location => "/build?level=0;pid=".$pid); 
	}

	
    $datasource->rollback;

    return OK;
}

# BULK DATA
#

sub data {
    my ($r, $dbh, $variable) = @_;

		
    $variable->{pid} = get_pid($r);

#	if ($r->param('show_data')) {
		show_data($r, $dbh, $variable);
#	} else { 
#		insert_mail($r, $dbh, $variable);
#	}

    return OK;
}


# Allow uploads of CSV files either merging with the existing dataset or
# replacing it.
sub upload {
    my ($r, $dbh, $variable) = @_;

    use IO::Handle;

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);

    my $upload = $r->upload('data');
    die "Upload required" unless $upload->filename;


    # Apache2::Upload incorrectly blesses the filehandle (bad XS typemap) so
    # Text::CSV_XS::getline fails as it's a method call against Apache2::Upload
    # instead of the file handle (which was extended by IO::Handle).
    my $fh  = $upload->fh;
       $fh = *$fh{IO};

    # Remove all existing data if we're replacing instaead of appending.
    $datasource->do('DELETE FROM data') if $r->param('replace');

    # TODO Check upload->type for text/plain or text/comma-separated-values
    # and test different OS/browsers.

    my $csv = Text::CSV_XS->new({ binary => 1, eol => $/ });
    
    # The first line of the file is the field headings.
    my @header = do { $csv->parse( $fh->getline ); $csv->fields }
        or die "Couldn't parse CSV file.";

    # Get the headers from the database.
    my $cols = $datasource->selectall_hashref('SELECT * FROM field', 'label');
    $cols->{id} = { name => 'id', label => 'ID', type => 'int' };

    my @cols;
    for my $i (0..$#header) {
        my $name = $header[$i];

        next unless $name && $cols->{$name};

        $cols->{$name}{i} = $i;
        
        push @cols, $cols->{$name};
    }
    die "Input header doesn't match any template fields." unless @cols;

    my @indices = map { $_->{i} } @cols;

    # Build the query and insert/update the record.
    my $fields       = join ',', map { $datasource->quote_identifier($_->{name}) } @cols;
    my $placeholders = join ',', ('?') x @cols;

    my $sth = $datasource->prepare(qq{
        INSERT OR REPLACE INTO data ($fields) VALUES ($placeholders)
    });

    my $map_assets = create_asset_lookup($datasource, \@cols);

    # Process the file.
    while (my $row = $csv->getline($fh)) {
        # Map any asset names to their IDs.
        $map_assets->( $row );

        $sth->execute( @{ $row }[ @indices ] );
    }

    $datasource->commit;

    my $query  = "?pid=$pid";
       $query .= ";create_to_order=1" if $r->param('create_to_order');

    $r->status(HTTP_MOVED_TEMPORARILY);
    $r->headers_out->set(Location => OVERVIEW_PAGE . $query);
    return HTTP_MOVED_TEMPORARILY;
}
sub show_data {
    my ($r, $dbh, $var) = @_;

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);
}

# insert_mail is no longer userd. This is an older version of the custom
# mailing changes request by dominos.
#sub insert_mail {
#    my ($r, $dbh, $var, $pid, $qty) = @_;
#
#	my $list = lc $r->param('mail_type');
#
#	die("Invalid Quantity: $qty -- Template::insert_mail") unless $qty;
#	die("Invalid Mailing Type ( param('mail_data') ) -- Template::insert_mail") unless $list;

#    my $datasource = get_datasource($dbh, $pid);

    # Get the headers from the database.
#    my $cols = $datasource->selectall_hashref('SELECT * FROM field', 'name');
#    $cols->{id} = { name => 'id', label => 'ID', type => 'int' };
#	print STDERR "Mail Dumper", Dumper($cols);

#	my $store = " AND location = '$var->{cust_id}' ";
#
#	my $where = $list eq 'late'   ? qq{ WHERE last_late::date > now() - interval '90 days' $store
#										ORDER by last_mail NULLS FIRST, last_late    } 
#			  : $list eq 'new'    ? qq{ WHERE first_order::date > now() - '60 days'::interval $store
#									    AND  last_order::date  > now() - '60 days'::interval 
#										ORDER by last_mail NULLS FIRST, last_order }
#			  : $list eq 'over90' ? qq{ WHERE last_order::date - '90 days'::interval  > prelast_order $store
#									  	ORDER by last_mail NULLS FIRST, last_order} 
#			  : q{};
#
#	my $limit = qq{LIMIT $qty}; 
##	my $limit = qq{LIMIT 10}; 
#
#	my $sql = qq{SELECT * FROM marketing_data $where $limit};
#
#	my $data = $dbh->selectall_arrayref($sql,{Slice => {}});
#
#print STDERR "DATA LOOKUP : \n $sql \n";
#
#	while ( @{$data} ) { 
#		$dbh->do(q{
#			UPDATE marketing_data SET last_pid = ? 
#			WHERE location = ? AND NAME = ? AND street_name = ? AND street_num = ?
#		}, undef, $pid, $var->{cust_id}, $_->{name}, $_->{street_name}, $_->{street_num}); 
#			
#
#	} # new end while
#	  my %rec;

#		$dbh->do(q{
#			UPDATE marketing_data SET last_mail = NOW() WHERE location = ? 
#			AND NAME = ? AND street_name = ? AND street_num = ?
#		}, undef, $var->{cust_id}, $_->{name}, $_->{street_name}, $_->{street_num}); 
		
#	  foreach my $i ( 1 ) {
#		$_ = shift @{$data};
#	  	next unless $data;
#
#		my $a = "AddressLineA$i";
#		my $b = "AddressLineB$i";
#		my $c = "AddressLineC$i";
#
#		$rec{$a}  = qq{$_->{name}};
#		$rec{$b}  = qq{$_->{suite}};
#		$rec{$b} .= '-' if $_->{suite};
#		$rec{$b} .= qq{$_->{street_num} $_->{street_name}};
#		$rec{$c}  = qq{$_->{city} $_->{province}  $_->{postal_code}};

#		$rec{"Customer_Name$i"} 	 = $rec{$a};
#		$rec{"Postal_Code$i"}   	 = $rec{$b};
#		$rec{"City_Provience$i"}     = $rec{$c};

#		delete $rec{$a};
#		delete $rec{$b};
#		delete $rec{$c};

#	  	print STDERR "DATA Dumper", Dumper(\%rec);
#	  }


#      # Build the query and insert/update the record.
#   	  my $fields       = join ',', map { $datasource->quote_identifier($_) } keys %rec;
#      my $placeholders = join ',', ('?') x keys %rec;
#	
#	print STDERR "INSERT - $pid  " , Dumper($fields, $placeholders, \%rec);
#	  my $sth = $datasource->prepare(qq{
#        INSERT OR REPLACE INTO data ($fields) VALUES ($placeholders)
#      });
#	  $sth->execute(values %rec);
#
#	}; #end while

#	$datasource->commit();


#}


# Creates a function that maps asset names to their ID for DB insertion.
sub create_asset_lookup {
    my ($dbh, $fields) = @_;

    # Prefetch all the asset lookups.
    my (%lookup, @assets);
    for my $field (@$fields) {
        next unless $field->{type} eq 'image' || $field->{type} eq 'pdf';

        my $table = $dbh->quote_identifier("asset_$field->{name}");

        $lookup{ $field->{i} } = { @{ $dbh->selectcol_arrayref(
            qq{ SELECT "name", id FROM $table }, 
        { Columns => [1, 2] }) } };

        push @assets, $field->{i};
    }

    # Return a closure that looks up IDs for the supplied names.
    return sub {
        my $row = shift;
        $row->[$_] = $lookup{$_}{ $row->[$_] } || undef for @assets;
    };
}


# Allow the user to download a CSV copy of their primary data table.
sub download {
    my ($r, $dbh, $variable) = @_;

    # Type of file to export.
    my $type = lc($r->param('type') || 'csv');

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);

    my $csv = Text::CSV_XS->new({
            binary   => 1, # Allow UTF-8 (and embedded newlines)
            sep_char => $type eq 'tsv' ? "\t" : ',',
    }); 

    my $sth = $datasource->prepare(q{SELECT * FROM export});
    $sth->execute;

    # Send the field names as a header then the body data.
    $variable->{File_Data} = [ 
        do { $csv->combine(@{ $sth->{NAME} }); $csv->string }, $/ 
    ];

    while (my $rec = $sth->fetch) { 
#use Data::Dumper;
#print STDERR "Rec: " , Dumper($rec);
        $csv->combine(@$rec);
		my $str = $csv->string;
		$str =~ s/•/\x{0095}/;

#print STDERR "String: " , Dumper($str);

        push @{ $variable->{File_Data} }, $str, $/;
    }

    # Set our output headers for our file type.
    $r->content_type('text/comma-separated-values');

    my $filename = $variable->{Download} = "$pid-template.$type";

    my $mime_type = $type eq 'csv' ? 'text/comma-separated-values' 
                                   : 'text/plain';

    $r->headers_out->{'Content-Disposition'} = qq{attachment; filename="$filename"};
    $r->content_type(qq{$mime_type; name="$filename"} );

    return OK;
}


# RECORD LEVEL CONTROLS
#

use constant LINE_HEIGHT => 1.4; # Line height is n % more than point size.

# View an individual record.
sub view_record {
    my ($r, $dbh, $variable) = @_;

    my $pid        = get_pid($r);
    my $info       = get_template_info($dbh, $pid);
    my $datasource = get_datasource($dbh, $pid);

    # Update the current record if we're being posted to. TODO Do we want
    # record controls ('next', 'prev', etc.) to always save changes?
    if ($r->method eq 'POST') {
        if ($r->param('delete')) { delete_record($r, $datasource); } 
        else                     { change_record($r, $datasource, $dbh, $variable->{cust_id}); }
    }

use Data::Dumper;
print STDERR "VIEW RECORD";
    # Adjust the record offset (current record being viewed).
    my $offset = $r->param('offset');
       $offset =~ tr/0-9//cd;
       $offset = update_offset($r, $datasource, $offset || 0);

    # The form is created from the page info extracted from the PDF template.
    $variable->{pages} = $info->{pages};

    # Determine text area sizing.
    for my $block ( @{ $info->{blocks} } ) {
        next unless $block->{Subtype} eq 'Text';

        my $bounds = $block->{Rect};

        my $width  = abs($bounds->[0] - $bounds->[2]);
        my $height = abs($bounds->[1] - $bounds->[3]);

        # We're going to assume an M's advance width is the same as it's
        # baseline to baseline measurement (ie. point size).
        $block->{cols} = int( $width  / ($block->{fontsize}) );
        $block->{rows} = int( ($height / $block->{fontsize}) * LINE_HEIGHT ) || 1;

        $block->{cols} = 4 if $block->{cols} < 4;

        $block->{scrollbar}  = 'auto';

        # If we're too large add a scrollbar to the text area.
        if ($block->{rows} > 10) {
            $block->{rows}       = 10;
            $block->{cols}      += 2;         # Extra space for scrollbar
            $block->{scrollbar}  = 'scroll';
        }

        # An input is instead a textarea when it's multi-line and marked as a
        # textflow block.
        $block->{textarea} = 1 if $block->{rows} > 1 && $block->{textflow};
    }

    # Get the current record or populate with defaults if it doesn't exist.
    my $record = $datasource->selectrow_hashref(qq{
        SELECT * FROM data LIMIT 1 OFFSET $offset
    });

    # Get a list of assets available (if applicable).
    my $fields = $datasource->selectcol_arrayref(q{
        SELECT name FROM field WHERE type <> 'text'
    });

    my $template_id = $datasource->selectrow_array(q{
        SELECT id FROM template_id 
    });

    for my $field (@$fields) {
        my $table = $datasource->quote_identifier("asset_$field");

        $variable->{assets}{$field} = $datasource->selectall_arrayref(qq{
            SELECT id, name FROM $table ORDER by id
        }, { Slice => {} });

		#global_assets($field, $variable->{assets}{$field}, $datasource);
    }
#print STDERR "ASSETS CHECK: ", Dumper($varia/ble->{assets});

    my $b = chr(8226);
    map { 
	    $record->{$_} = decode_utf8($record->{$_}); 
	    $record->{$_} =~ s/\x{e2}\x{80}\x{a2}/$b/;
	    $record->{$_} =~ s/\x{fffd}/$b/; 

    } keys %$record;




print STDERR "CHECKING DEFAULTS FOR: $variable->{cust_id} \n";

	unless (%$record) {
print STDERR "NO RECORD FOUND \n\n";

		#my $data = $dbh->selectall_arrayref(q{
		#	SELECT field, value FROM template_defaults
		#	WHERE template = ?
		#	AND name  = (SELECT strcompanyname FROM tbl_customer
		#				 WHERE lngcustomerid = ?)
		#},{Slice => {}},$template_id, $variable->{cust_id});

		my $data = $dbh->selectall_arrayref(q{
			SELECT field, value FROM template_defaults
			WHERE  name  = (SELECT strcompanyname FROM tbl_customer
						 	WHERE lngcustomerid = ?)
		},{Slice => {}}, $variable->{cust_id});
		map { $record->{$_->{field}} = $_->{value} } @{$data};

	}
	if ( $r->param('reload_page') ) {
		$variable->{'reload_page'} = $r->param('reload_page');
	}
	$variable->{'marker'} = time();
	
print STDERR "HAVE PDF RELOAD: $variable->{reload_page}- $variable->{marker} \n";


    $variable->{__FillInForm} = keys %$record 
        ? $record 
        : { map { $_->{Name} => $_->{default} } @{ $info->{blocks} } };


    $datasource->rollback;

    $variable->{pid}             = $pid;
    $variable->{offset}          = $offset;
    $variable->{create_to_order} = $r->param('create_to_order') 
        if $r->param('create_to_order');

    return OK;
}

# Change records (based on current offset) TODO Streamline controls on HTML
# side so it's simpler here.
sub update_offset {
    my ($r, $datasource, $offset) = @_;

    my $max = $datasource->selectrow_array(q{
        SELECT count(*)-1 FROM data
    });
print STDERR "UPDATE MAX: $max OFF: $offset \n";

    $offset = $max if $offset > $max && $max > 0;

    my $next = $offset + 1 > $max ? $max : $offset + 1;
    my $prev = $offset - 1 < 0    ? 0    : $offset - 1;

    return $r->param('next')  ? $next
         : $r->param('prev')  ? $prev
         : $r->param('first') ? 0
         : $r->param('last')  ? $max
         : $r->param('new')   ? $max + 1
         :                      $offset;
}

# Insert/update a record.
sub change_record {
    my ($r, $datasource, $dbh, $cust_id) = @_;

print STDERR "CHANGE RECORD - TRANSACTION \n";
map { print STDERR "PARAMS: $_ = ", $r->param($_) , "\n" } $r->param(); 
#$dbh->do("begin") or die $dbh->errstr;
    # Get the fields we're interested in. TOOD Just build from passed form
    # fields ?
    my $sth = $datasource->prepare('SELECT * FROM data LIMIT 0');
    $sth->execute;
    my @fields = @{ $sth->{NAME} };

    my @fields = @{ $sth->{NAME} };

    # Get the value for our fields.
    my @values = map { $r->param($_) || undef } @fields;
    

use Encode;
    my $b = '\x{e2}\x{80}\x{a2}';

    map { $_ =~ s/•/$b/;print STDERR "VALUE: " . encode_entities($_) . " \n"; } @values;

	my $name = $dbh->selectrow_array(q{
		SELECT strcompanyname FROM tbl_customer WHERE lngcustomerid = ?
	}, undef, $cust_id);

    my $template = $datasource->selectrow_array(q{
        SELECT id FROM template_id 
    });

	my $del = $dbh->prepare(q{
		DELETE FROM template_defaults WHERE template = ? and name = ?
	});

	$del->execute($template, $name);

	my $defaults = $dbh->prepare(q{
		INSERT INTO template_defaults ( template, name, field, value )
		VALUES ( ?, ? ,?, ? )
	});

	my $i;

	map { $defaults->execute($template, $name, $_, $values[$i] ) unless $_ eq 'id'; $i++ } @fields;

	unless ( grep {$cust_id eq $_} MULTI ) {
print STDERR "******* CUSTOMER : $cust_id is not allowed multiple records ******** \n";

		$values[0] = 1;
print STDERR "FORCING ID to 1 to prevent multiple records \n ";
	} else {
		print STDERR " ********  Allow multiple records for : $cust_id ******** \n";
	}
print STDERR "Record data for INSERT \n " , Dumper(\@fields, \@values);



    # Build the query and insert/update the record.
    my $fields       = join ',', map { $datasource->quote_identifier($_) } @fields;
    my $placeholders = join ',', ('?') x @values;

print STDERR "INSERT OR REPLACE", Dumper($fields, \@values);

    $sth = $datasource->prepare(qq{
        INSERT OR REPLACE INTO data ($fields) VALUES ($placeholders)
    });
    $sth->execute(@values);

	# only do this for mailing projects.
	if ( $r->param('AddressLineA1') ) {

	my @no_up = qw(id AddressLineA1 AddressLineB1 AddressLineC1);

	my @up_list;
	foreach my $f ( @fields ) {
		push @up_list, $f unless grep($f eq $_, @no_up);
	}
	print STDERR "UPDATING FIELDS:  \n" , Dumper(\@up_list);
	print STDERR "UPDATING VALUES:  \n" , Dumper($r->param('8564_d'));

	map {
		my $up = $datasource->prepare(qq{ UPDATE data set } . $datasource->quote_identifier($_) . qq{ = ? });
		$up->execute($r->param($_));
	} @up_list;

	}

    $datasource->commit;
	

    return 1;
}

# Delete one or more records.
sub delete_record {
    my ($r, $datasource) = @_;

    # Allow multiple deletes at once.
    my @ids = grep { $_ } map { tr/0-9//cd; $_ } $r->param('id');

    my $sth = $datasource->prepare(q{DELETE FROM data WHERE id = ?});
    $sth->execute($_) for @ids;

    $datasource->commit;

    return 1;
}


# ASSET CONTROLS (IMAGE/PDF)
#

sub assets {
    my ($r, $dbh, $variable) = @_;

    my $pid        = get_pid($r);
    my $info       = get_template_info($dbh, $pid);
    my $datasource = get_datasource($dbh, $pid);

	if ( $r->param('sync') ) {
		my @fields = $r->param('field');
		map {
			sync_asset($r, $dbh, $variable, $_);
		} @fields;
    	$r->status(HTTP_MOVED_TEMPORARILY);
    	$r->headers_out->set(Location => ASSET_PAGE . "?pid=$pid");
    	return HTTP_MOVED_TEMPORARILY;
	}

    $variable->{pid} = $pid;
    $variable->{create_to_order} = $r->param('create_to_order') 
        if $r->param('create_to_order');

    # Get any image/pdf fields
    my $fields = $datasource->selectall_arrayref(q{
        SELECT name, label FROM field WHERE type <> 'text';
    }, { Slice => {} });

    return OK unless @$fields;

    # Get a list of assets for each field.
    for my $field (@$fields) {
        my $table = $dbh->quote_identifier("asset_$field->{name}");

        $field->{assets} = $datasource->selectall_arrayref(qq{
            SELECT id, name FROM $table
        }, { Slice => {} });
    }

    $variable->{fields} = $fields;

    return OK;
}

sub upload_asset {
    my ($r, $dbh, $variable) = @_;

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);

    my $path = get_path(undef, $dbh, $pid) . '.template/'
        or die "Can't find project files.";

	if ( $r->param('sync') ) {
		sync_asset($r, $dbh, $variable);
    	$r->status(HTTP_MOVED_TEMPORARILY);
    	$r->headers_out->set(Location => ASSET_PAGE);
    	return HTTP_MOVED_TEMPORARILY;
	}
    my $asset  = $r->param('field');
    my $name   = $r->param('name');
    my $upload = $r->upload('file');

    die "Invalid upload" unless $upload && $name && $asset;
    # $upload->type eq 'application/pdf' 'image/*'

    # Insert an entry into the DB.
    my $table = $datasource->quote_identifier("asset_$asset");
    $datasource->do(qq{INSERT INTO $table (name) VALUES (?)}, undef, $name);

    my $id = $datasource->last_insert_id(undef, undef, undef, $table);

    # Spool the asset out to disk.
    open(my $fh,">","$path/assets/$asset/$id")
        or die "Couldn't open asset file ($path/assets/$asset/$id) $!";

    binmode $fh;
    my $up = $upload->fh;
    print $fh $_ while <$up>;
    $fh->close or die "Couldn't close asset file: $!";

    $datasource->commit;

    my $query  = "?pid=$pid";
       $query .= ";create_to_order=1" if $r->param('create_to_order');

    $r->status(HTTP_MOVED_TEMPORARILY);
    $r->headers_out->set(Location => ASSET_PAGE . $query);
    return HTTP_MOVED_TEMPORARILY;
}

sub sync_asset {
    my ($r, $dbh, $variable, $asset) = @_;

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);

    my $path = get_path(undef, $dbh, $pid) . '.template/'
        or die "Can't find project files.";

	my $gpath =  $r->document_root .
				'/site_specific/customers/assets/' . $asset;

print STDERR "START SYNC FIELD: $asset \n";

	opendir my $dirhandle, $gpath or print STDERR "Couldn't open asset directory ($path): $!";

	my %list;
	while (my $name = readdir($dirhandle)) {
    	next if substr($name, 0, 1) eq '.' || ! -f "$gpath/$name";

		my $key = $name;
		$key =~ s/\$//;
		$key =~ /(\d*)/;
		$key = $1 if $1;

		$list{$key} = $name;
	}

	my @slist =  sort { $a <=> $b } keys %list;

	use Data::Dumper;
print STDERR Dumper(@slist);

	map {
		my $name = $list{$_};


print STDERR "SYNC: $name KEY: $_ \n";

		open(my $up, "<", "$gpath/$name") || die("Could not open $gpath/$name \n");


		die "Invalid upload" unless $up && $name && $asset;
		# $upload->type eq 'application/pdf' 'image/*'

		$name =~ /(.*)\./;

		my $fname = $1 || $name; 

		# Insert an entry into the DB.
		my $table = $datasource->quote_identifier("asset_$asset");

		my $id = $datasource->selectrow_array(qq{
			SELECT id FROM $table WHERE name = ?
		}, undef, $fname);

		$datasource->do(qq{INSERT INTO $table (name) VALUES (?)}, undef, $fname) unless $id;
		$id = $datasource->last_insert_id(undef, undef, undef, $table) unless $id;

		# Spool the asset out to disk.
		open(my $fh, ">", "$path/assets/$asset/$id")
			or die "Couldn't open asset file ($path/assets/$asset/$id) $!";

		binmode $fh;
		#my $up = $upload->fh;
		print $fh $_ while <$up>;
		$fh->close or die "Couldn't close asset file: $!";

	} @slist;

    $datasource->commit;

    return HTTP_MOVED_TEMPORARILY;
}


# Delete one or more assetss.
sub delete_asset {
    my ($r, $dbh) = @_;

    my $pid        = get_pid($r);
    my $datasource = get_datasource($dbh, $pid);

    my $path = get_path(undef, $dbh, $pid) . '.template/'
        or die "Can't find project files.";

    # Allow multiple deletes at once.
    my @ids    = grep { $_ } map { tr/0-9//cd; $_ } $r->param('id');
    my $table = $datasource->quote_identifier('asset_' . $r->param('field'));

    my $sth = $datasource->prepare(qq{DELETE FROM $table WHERE id = ?});
    $sth->execute($_) for @ids;

    $datasource->commit;

    my $query  = "?pid=$pid";
       $query .= ";create_to_order=1" if $r->param('create_to_order');

    $r->status(HTTP_MOVED_TEMPORARILY);
    $r->headers_out->set(Location => ASSET_PAGE . $query);
    return HTTP_MOVED_TEMPORARILY;
}

1;

