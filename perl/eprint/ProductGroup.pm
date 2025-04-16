package eprint::ProductGroup;
use strict;
use warnings;

use Apache2::Const qw(OK HTTP_MOVED_TEMPORARILY);
use Data::Dumper;
use Iterator;
use Iterator::Util qw(iarray);
use Iterator::Misc;
use eprint::qprice;

use base qw(Exporter);
our @EXPORT_OK = qw(questions assigned_project matrix_table);


# PAGE HANDLERS
#

sub display_category {
    my ($r, $dbh, $variable) = @_;

    return misc::error($r->log, $dbh, $variable, 'User Not Found', 
        "Please login to see products."
    ) unless $variable->{cust_id};

    my $category = $r->param('category');
       $category =~ tr/0-9a-zA-Z_//cd;
       $category = lc $category;

    # Check to see if the optional category include exists.
    my $site_specific = $r->dir_config('site_specific') || $r->document_root . '/site_specific';
    my $include = "includes/products/$category.html";

    $variable->{include} = -e "$site_specific/$include" ? "/site_specific/$include" : undef;

    # Get the category information.
    $variable->{category} = $dbh->selectrow_hashref(q{ SELECT * FROM product.category WHERE name = ? }, undef, $r->param('category'));


    my $sql = qq{ SELECT lnguserid, strfirstname || ' ' || strlastname FROM tbl_customer_users 
				 WHERE lngcustomerid = $variable->{cust_id} AND ysnaccountactivation ='Y' ORDER BY 2 };

    $variable->{USERS} = ssi::fill_drop_down( $r->log, $dbh, $sql, undef);

#print STDERR "USERS DUMPER " , Dumper($variable->{USERS});

    # Get all the items in the current category.
    $variable->{items} = [ 
        map { my $item = eval { item($dbh, $_->[0], $variable->{cust_id}) }; 
              if ($@) { () }                             # Invalid items are removed.
              else    { $item->{view} = $_->[1]; $item } 
            } 
           @{ $dbh->selectall_arrayref(q{ SELECT item, initial_view FROM product.item_category WHERE category = ?  ORDER BY sort }, undef, $variable->{category}{id}) }
    ];

#Addd current year plus future years.
	my @time = localtime(time);
	my $year = 1900 + $time[5];
	map { push @{$variable->{YEARS}}, {year=>$_+$year} } (0..3);

  return misc::error($r->log, $dbh, $variable, 'Not Found', "There are no products in this category.") unless @{ $variable->{items} };

  return OK;
}

# Map the selections from a "product selector" form to a predifined project. 
sub select_project {
  my ($r, $dbh , $var) = @_;

  my $item = $r->param('item');
  $item =~ tr/0-9//cd;

  die "Invalid or no predefined selector item found." unless $item;

  # If they've chosen a specific item from the matrix we can just use that.
  my $predefined = $r->param('pid') || $r->param('auto_pid');

  unless ($predefined) {
    # Otherwise we need to see if a projects exists at the intersection of the
    # answers in the cross product.
    my @answers = map { $_ = $r->param($_); tr/0-9//cd; $_ } 
    grep /^q\d+$/, $r->param;

    ($predefined) = assigned_project($dbh, $item, @answers);

    die "No project found based on selections." unless $predefined;
  }

	if ( $r->param('auto_pid') ) {
		#Validate the Delivery date to prevent problems downstream.
		#check_date (yyyy, mm, dd)
		use Date::Calc qw/check_date/;
		my @date =  ($r->param('ddmDueDateYear1'), $r->param('ddmDueDateMonth1'), $r->param('ddmDueDateDay1'));

		return misc::error( $r->log, $dbh, $var, 'Invalid Delivery Date', 'Please press the Back button and enter a valid Delivery Date' ) unless check_date(@date);

		my $pid = eprint::qprice::auto_product($r, $dbh, $var, $predefined);
		
		# recalc project if we have one. else will be redirected to custom error page.
		$r->headers_out->set( Location => "/build?pid=$pid;level=0") if $pid;
	} else {
		# Send the user to the create page with their selected predefined project.
		$r->headers_out->set( Location => "/main/proj/create.html?predefined=$predefined");
	}

	$r->status(HTTP_MOVED_TEMPORARILY);
  return HTTP_MOVED_TEMPORARILY;
}


# SUPPORT FUNCTIONS
#

# Gets a hash representing the the item.
sub item {
    my ($dbh, $id, $cust_id) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT name, description, image, pid FROM product.item WHERE id = ?
    });

    my ($name, $description, $image, $pid) = $dbh->selectrow_array($sth, undef, $id);

    die "Invalid item id ($id) or no item found.\n" unless $id && $name;

    my $questions = questions($dbh, $id);

	my $opt = $dbh->selectall_arrayref(q{
		SELECT max(lngindex) as lngindex, strname, strcategory, strfinish, strweight, strcolour
	 	FROM tbl_paper WHERE lngindex in ( 
			SELECT paper from product.item_paper WHERE item = ?)
		GROUP by strname, strcategory, strfinish, strweight, strcolour

		UNION

		SELECT max(lngindex) as lngindex, strname, strcategory, strfinish, strweight, strcolour
	 	FROM tbl_paper_roll WHERE lngindex in ( 
			SELECT paper from product.item_paper WHERE item = ?)
		GROUP by strname, strcategory, strfinish, strweight, strcolour
		ORDER by strname, strcategory, strfinish, strweight, strcolour
		
	},{Slice => {}}, $id, $id);

    my $services = $dbh->selectcol_arrayref(q{
         SELECT strid FROM tbl_service_types WHERE lngindex IN (
             SELECT service FROM product.item_service WHERE item = ?
         )
    },{Slice=>{}}, $id);

	my $list;
	map { $list->{$_}=1 } @{$services}; 
	$list->{Bindery} = 1 if grep {$list->{$_}} qw(CornerStitching Cerlox DoubleLoopWire MetalCoil PlasticCoil PerfectBinding SaddleStitching 3HolePunch Proclick SingleHole );

	my $type = $dbh->selectrow_array(q{
		SELECT strid FROM tbl_equipment_type, tbl_projects 
		WHERE lngprojectindex = ?
		AND lngpresstype = lngindex
	}, undef, $pid);

print STDERR "HAVE SERVICES Type: $type " , Dumper($services, $list);

    return {
        id          => $id,
		pid			=> $pid,
        name        => $name,
        description => $description,
        image       => $image,
        questions => $questions,
        matrix    => matrix_table($dbh, $id, $questions, $cust_id),
		stock_options => $opt,
		service => $list,
		press_type => $type
    };
}


# Get the questions and possible answers for the given item.
sub questions {
    my ($dbh, $item) = @_;

    my $question = $dbh->prepare(q{
        SELECT id, label FROM product.question WHERE item = ? ORDER BY sort, id
    });
    my $answer   = $dbh->prepare(q{
        SELECT id AS n, label 
        FROM product.answer 
        WHERE question = ? 
        ORDER BY sort, id
    });

    $question->execute($item);

    my @questions;
    while (my ($id, $label) = $question->fetchrow_array) {
        push @questions, { 
            id      => $id, 
            label   => $label,
            answers => $dbh->selectall_arrayref($answer, { Slice => {} }, $id), 
        };
    }

    die "No questions found for item ($item)" unless @questions;

    return \@questions;
}

# Get the project id and label of the project assigned to a given answer set.
sub assigned_project {
  my ($dbh, $item, @answers) = @_;

  die "Must provide at least one answer." unless @answers;

  my $answers = join ', ', @answers;

  my ($pid, $name, $qty, $id) = $dbh->selectrow_array(qq{
    SELECT a.project, a.label, a.qty, a.id
    FROM product.assignment a, product.answer_set s
    WHERE a.id = s.assignment
    AND s.answer IN ($answers)
    GROUP BY a.project, a.label, a.qty, a.id, s.assignment
    HAVING count(s.assignment) = (
    SELECT count(*) FROM product.question WHERE item = ? )
    }, undef, $item);

  return $pid, $name, $qty, $id;
}

# Create the data structure needed to create the pivot table view of the
# possible projects (cartesian product of possible answers). TODO Pretty
# sloppy, clean this up.
sub matrix_table {
    my ($dbh, $item, $questions, $cust_id) = @_;

	my $markup = modify_label($dbh, $item, $cust_id) || 0;
    # Define the labels for the headers of the non-pivot table section.
    my @headers =  map { { name => $_->{label} } } 
                   map { $questions->[$_] } 
                       0 .. $#{ $questions }-1;

    my $set = scalar @$questions > 1 
        ? cross_product( map { $_->{answers}  } 
                         map { $questions->[$_] } 
                              0 .. $#{ $questions }-1 
                       ) 
        : iarray([undef]); # Single questions only have a pivot.

    # The last (user ordered) field is pivotted over.
    my $pivot = $questions->[-1];
    my @pivot = map { $_->{n} } @{ $pivot->{answers} };

    my @rows;
    while ($set->isnt_exhausted) {
        my $data = $set->value;

        my @cols;
        my @answers;




        # If there was more than one question, get the columns.
        if ($data) {
            @cols    = map { { label => $_->{label} } } @$data; # Answer labels.
            @answers = map { $_->{n} } @$data;
        }

        # Get the projects that are assigned to this product.
        push @cols, map { 
            my ($pid, $label) = assigned_project($dbh, $item, @answers, $_); 
			$label =~ /\$(\d*\.*\d*)/;
			if ( $1 ) {
				$label = '$' . sprintf("%.2f", $1 * (1 + ( $markup / 100)));
			}

print STDERR "HAVE LABEL : $label \n";

            
            { pivot => 1,     label => $label, 
              pid   => $pid,  set   => join('-', @answers, $_) }; 
        } @pivot;

        push @rows, { data => \@cols };
    }

    # Take a second pass to span labels across rows if they can be grouped.
    my @prev;
    for my $row (@rows) {
        my $data   = $row->{data};
        my $remove = 0;

        for my $i (0 .. $#{ $questions }-1) {
            my $label = $data->[$i]{label};

            if (!defined $prev[$i] || $prev[$i]{label} ne $label) {
                $prev[$i] = $data->[$i];
            }
            else {
                $prev[$i]{span} = 1 unless exists $prev[$i]{span};

                $prev[$i]{span}++;
                $remove++;         # Mark spanned over cells for removal.
            }
        }
        shift @$data for 1..$remove;
    }

    # Return the structure needed to generate the table.
    return {
        headers    => \@headers,
        pivot_name => $pivot->{label},
        pivot_size => scalar @{ $pivot->{answers} },
        pivot_cols => [ map { {name => $_->{label}} } @{$pivot->{answers}} ],

        rows => \@rows
    };
}

sub modify_label {
	my $dbh = shift;
	my $item = shift;
	my $cust_id = shift;
	

	print STDERR "START MODIFY LABEL: $item,   $cust_id, \n";

	my $markup = $dbh->selectrow_array(q{
		SELECT markup from product_markup m, product.item_category ic WHERE customer = ? and ic.category = m.category AND ic.item  = ?
	}, undef, $cust_id, $item);

	print STDERR "MODIFY LABLE: $item,   $cust_id, $markup \n";

	return $markup;


}


1;
