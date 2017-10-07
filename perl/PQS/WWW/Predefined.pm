package PQS::WWW::Predefined;
use strict;
use warnings;
use utf8;

use Apache2::Const qw(:common :http);
use Apache2::Request ();

use eprint::ProductGroup qw(questions assigned_project matrix_table);

use base qw(Exporter);

our @EXPORT = qw(
    categories  category  modify_category
    items       item      modify_item
                question  modify_question
);   #    projects    define

# Display product categories.
sub categories {
    my $r   = shift;
    my $t   = shift;
    my $dbh = $r->pnotes('dbh');

    my $categories = $dbh->selectall_arrayref(q{
        SELECT * FROM product.category ORDER BY "name"
    }, { Slice => {} });

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/categories.html';

    print $t->process(
        title => 'Predefined Product Categories',
        categories => $categories,
    );

    return OK;
}

# Display a product category and sort ordering/initial view (matrix or
# questions) for items in the category.
sub category {
    my $r   = shift;
    my $t   = shift;
    my $dbh = $r->pnotes('dbh');

    my $id = $r->param('id');
       $id =~ tr/0-9//cd;

    my $category = $dbh->selectrow_hashref(q{
        SELECT * FROM product.category WHERE id = ?
    }, undef, $id);

    my $products = $dbh->selectall_arrayref(q{
        SELECT i.id, i."name", a.sort, a.initial_view
        FROM product.item i, product.item_category a
        WHERE i.id       = a.item
          AND a.category = ?
        ORDER BY a.sort, i."name"
    }, { Slice => {} }, $id);

    $category->{has_products} = scalar @$products;
    $category->{products}     = $products;

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/category.html';

    print $t->process(
        title    => 'Predefined Product Category',
        category => $category,
    );

    return OK;
}

# Create, delete, or update a category.
sub modify_category {
    my $r   = shift;
    my $dbh = $r->pnotes('dbh');

    # Remove categories if a delete was requested.
    if ( $r->param('delete') ) {
        my $ids = join ',', grep defined, map { tr/0-9//cd; $_ } $r->param('id');

        $dbh->do("DELETE FROM product.category WHERE id IN ($ids)");
        $dbh->commit;

        $r->headers_out->set(Location => "/admin/categories");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return OK;
    }

    my $id = $r->param('id');
       $id =~ tr/0-9//cd;

    # Create a new category.
    if (!$id) {
        die "A name must be supplied to create a category." 
            unless $r->param('name');

        $dbh->do(q{
            INSERT INTO product.category (name) VALUES (?)
        }, undef, $r->param('name'));

        #$id = $dbh->last_insert_id('', 'product', 'category', 'id');
        $id = $dbh->selectrow_array(q{SELECT max(id) FROM product.category});
        $dbh->commit;
    }
    else {
        # Update the name.
        $dbh->do(q{
            UPDATE product.category SET name = ? WHERE id = ?
        }, undef, $r->param('name'), $id);
        
        # Change any sort ordering or initial view assignments.
        for my $item ($r->param('items')) {

            # If the sort order isn't defined it defaults to 0.
            my $sort = $r->param("sort-$item");
               $sort =~ tr/0-9//cd;

            # Matrix or Question view.
            my $view = $r->param("view-$item") eq 'M' ? 'M' : 'Q';

            $dbh->do(q{
                UPDATE product.item_category SET sort = ?, initial_view = ?
                WHERE item = ?
            }, undef, $sort || 0, $view, $item);
        }

        $dbh->commit;
    }

    # Send them back from whence they came.
    $r->headers_out->{Location} = "/admin/category?id=$id";
    $r->status(HTTP_MOVED_TEMPORARILY);
    return OK;
}


# Display all "products" in the database.
sub items {
    my $r   = shift;
    my $t   = shift;
    my $dbh = $r->pnotes('dbh');

    my $items = $dbh->selectall_arrayref(q{
        SELECT * FROM product.item ORDER BY "name"
    }, { Slice => {} });

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/items.html';

    print $t->process(
        title => 'Predefined Project Setup',
        items => $items,
    );

    return OK;
}

# Display a specific "product".
sub item {
    my $r   = shift;
    my $t   = shift;
    my $dbh = $r->pnotes('dbh');

    my $id = $r->param('id');
       $id =~ tr/0-9//cd;

   # die "Invalid or no item defined." unless $id;

    # Basic item details.
    my $item = $dbh->selectrow_hashref(q{
        SELECT id, name, description, image, pid FROM product.item WHERE id = ?
    }, undef, $id);

	$item->{stock_url}         = '/admin/item_paper?item='   . $id;
	$item->{cover_stock_url}   = '/admin/item_cover_paper?item='   . $id;
	$item->{roll_url}    = '/admin/item_paper?item='   . $id .';type=roll';
	$item->{service_url} = '/admin/item_service?item=' . $id;
	
    # Categories for dropdown.
    $item->{categories} = $dbh->selectall_arrayref(q{
        SELECT c.id, c."name", i.selected AS selected
        FROM product.category c LEFT JOIN 
             ( SELECT category, true AS selected 
               FROM product.item_category 
               WHERE item = ?) i 
             ON (c.id = i.category)
    }, { Slice => {} }, $id);


    # Question/answers.
    my $questions = eval { questions($dbh, $id) };

    if (!$@) {
        $item->{questions} = $questions;

        # Predefined project assignment.
        $item->{matrix} = matrix_table($dbh, $id, $questions);
    }

    
    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/item.html';

    print $t->process(
        title  => 'Predefined Product Setup',
        item   => $item, 
        matrix => $item->{matrix}, 
    );

    return OK;
}

# Create, update, or delete an item (basic attributes and categories).
sub modify_item {
    my $r   = shift;
    my $dbh = $r->pnotes('dbh');

    if ($r->param('delete')) {
        my $ids = join ',', grep defined, map { tr/0-9//cd; $_ } $r->param('id');

        $dbh->do("DELETE FROM product.item WHERE id IN ($ids)");
        $dbh->commit;

        $r->headers_out->set(Location => "items");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return OK;
    }

 	if ($r->param('copy')) {
         my $id = $r->param('id');

         $dbh->do("INSERT INTO product.item (name, image, description, pid)  (SELECT name || ' Copy of ' || '$id', image, description, pid FROM product.item WHERE id = $id)");
		 my $new_item = $dbh->selectrow_array(q{SELECT MAX(id) FROM product.item});

		 my $q = $dbh->selectall_arrayref(qq{SELECT * FROM product.question WHERE item = ?}, {Slice=>{}}, $id);
use Data::Dumper;
print STDERR "HAVE STUFF ", Dumper($q);
		
        my $qin = $dbh->prepare("INSERT INTO product.question (item, label, sort, spec) VALUES ( ?, ?, ?, ?)");
		map {
			$qin->execute( $new_item, $_->{label}, $_->{'sort'}, $_->{spec});
		    my $new_q = $dbh->selectrow_array(q{SELECT MAX(id) FROM product.question});
	
		 	my $answers = $dbh->selectall_arrayref(qq{
					SELECT * FROM product.answer   WHERE question = ?
			}, {Slice=>{}}, $_->{id});

			foreach my $a (@{$answers}) {
         		$dbh->do("INSERT INTO product.answer(question, label, sort, value) VALUES ( 
							'$new_q', '$a->{label}', '$a->{sort}', '$a->{value}'
				)");
			}

print STDERR "HAVE STUFF ", Dumper($answers);
			
		} @{$q};

		my $s = $dbh->selectcol_arrayref(q{
			SELECT paper FROM product.item_paper WHERE item = ?
		}, undef, $id); 

		map { 
			$dbh->do(qq{INSERT INTO product.item_paper VALUES ( $new_item, $_ ) });
		} @{$s};

#Do the Same for Cover Stock

		my $s = $dbh->selectcol_arrayref(q{
			SELECT paper FROM product.item_cover_paper WHERE item = ?
		}, undef, $id); 

		map { 
			$dbh->do(qq{INSERT INTO product.item_cover_paper VALUES ( $new_item, $_ ) });
		} @{$s};


		
		my $s = $dbh->selectcol_arrayref(q{
			SELECT service FROM product.item_service WHERE item = ?
		}, undef, $id); 

		map { 
			$dbh->do(qq{INSERT INTO product.item_service VALUES ( $new_item, $_ ) });
		} @{$s};
		

         $dbh->commit;

         $r->headers_out->set(Location => "item?id=$new_item");
         $r->status(HTTP_MOVED_TEMPORARILY);
         return OK;
     }

    my $id = $r->param('id');
       $id =~ tr/0-9//cd;

    my ($name, $description, $image, $pid) = map { $r->param($_) || undef } 
                                           qw(name description image pid);

    die "Name is required." unless $name;

    # Create a new item.
    if (!$id) {
        $dbh->do(q{
            INSERT INTO product.item (name, description, image, pid) 
            VALUES (?, ?, ?, ?)
        }, undef, $name, $description, $image, $pid);

        $id = $dbh->last_insert_id('', 'product', 'item', 'id');
        #$id = $dbh->selectrow_array(q{SELECT max(id) FROM product.item});
    }
    else {
        # Update the item.
        $dbh->do(q{
            UPDATE product.item 
            SET name        = ?,
                description = ?,
                image       = ?,
				pid			= ?
            WHERE id = ?
        }, undef, $name, $description, $image, $pid, $id);
    }

    # Update the categories the item is in.
    update_item_categories($dbh, $id, 
        grep defined, map { tr/0-9//cd; $_ } $r->param('category'));
    
    update_item_matrix($r, $dbh, $id); 

    $dbh->commit;

    # Send them back from whence they came.
    $r->headers_out->{Location} = "item?id=$id";
    $r->status(HTTP_MOVED_TEMPORARILY);
    return OK;
}


sub update_item_categories {
    my ($dbh, $id, @cats) = @_;

    # We don't want to reset the ordering of any categories an item is already
    # in, so compare the current list and insert or delete as needed.
    my $insert = $dbh->prepare(q{
        INSERT INTO product.item_category (category, item) VALUES (?, ?)}
    );
    my $delete = $dbh->prepare(q{
        DELETE FROM product.item_category WHERE category = ? AND item = ? 
    });

    my $prev = $dbh->selectcol_arrayref(q{
        SELECT category FROM product.item_category WHERE item = ?
    }, undef, $id);

    my %intersect;
    $intersect{$_} += 2 for @$prev;
    $intersect{$_} += 1 for @cats;

    # 1 is only in new list - insert, 2 is only in old - delete, 3 is in both
    # so nothing need be done.
    while (my ($cat, $n) = each %intersect) {
        if    ($n == 1) { $insert->execute($cat, $id) }
        elsif ($n == 2) { $delete->execute($cat, $id) }
    }
}

sub update_item_matrix {
    my ($r, $dbh, $item) = @_;

    my $assignment = $dbh->prepare(q{ 
        INSERT INTO product.assignment (qty, item, project, label) VALUES (?,?,?,?) 
    });

    my $answer_set = $dbh->prepare(q{ 
        INSERT INTO product.answer_set (assignment, answer) VALUES (?, ?) 
    });

    # Remove existing assignments (easier than updates/merges).
    delete_item_matrix($dbh, $item);

    # For each matrix cell, record the project assigned to it and the answer
    # set that identifies that cell.
    for my $set ( grep defined, map { /^pid_([0-9-]+)$/; $1 } $r->param ) {
        my $pid = $r->param("pid_$set");
           $pid =~ tr/0-9//cd;

        next unless $pid;

        my $label = $r->param("label_$set") || undef;
        my $qty   = $r->param("qty_$set")   || undef;

        $assignment->execute($qty, $item, $pid, $label);
        my $assigned = $dbh->last_insert_id('', 'product', 'assignment', 'id');

        $answer_set->execute($assigned, $_) 
            for map { tr/0-9//cd; $_ } split /-/, $set;
    }
}

sub delete_item_matrix {
    my ($dbh, $item) = @_;

    return $dbh->do(q{DELETE FROM product.assignment WHERE item = ?}, undef, $item);
}

# Display a question and it's answers.
sub question {
    my $r   = shift;
    my $t   = shift;
    my $dbh = $r->pnotes('dbh');

    my $item = $r->param('item');
       $item =~ tr/0-9//cd;

    my $id   = $r->param('id');
       $id   =~ tr/0-9//cd;

    # Basic details.
    $item = $dbh->selectrow_hashref(q{
        SELECT id, name, description, image FROM product.item WHERE id = ?
    }, undef, $item);

    die "Invalid or no item defined." unless $item->{id};

    my $question = $dbh->selectrow_hashref(q{
        SELECT * FROM product.question WHERE item = ? AND id = ?
    }, undef, $item->{id}, $id);

    $question->{answers} = $dbh->selectall_arrayref(q{
        SELECT * FROM product.answer WHERE question = ? ORDER BY sort
    }, { Slice => {} }, $id);

    
    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/question.html';

    print $t->process(
        title    => 'Product Questions',
        item     => $item, 
        question => $question,
    );

    return OK;
}

# Modifies a question and it's answers.
sub modify_question {
    my $r   = shift;
    my $dbh = $r->pnotes('dbh');

    my $item = $r->param('item');
       $item =~ tr/0-9//cd;

    die "A product must be specified" unless $item;

    if ($r->param('delete')) {
        my $ids = join ',', grep defined, map { tr/0-9//cd; $_ } $r->param('id');

        my $n = $dbh->do("DELETE FROM product.question WHERE id IN ($ids)");

        # Removing questions invalidate the old matrix (though we could remove
        # the answers from the answer set and choose one of the multiple valid
        # assignments left).
        delete_item_matrix($dbh, $item) if $n;

        $dbh->commit;

        $r->headers_out->set(Location => "item?id=$item");
        $r->status(HTTP_MOVED_TEMPORARILY);
        return OK;
    }

    my $id   = $r->param('id');
       $id   =~ tr/0-9//cd;

    my $name = $r->param('question')
        or die "A question label is required.";
	my $spec = '';
	if ($name eq 'Color:' || $name eq 'Colors:'){
		$spec = 'colour';
	} elsif ($name eq 'Size:' || $name eq 'Sizes:'){
		$spec = 'size';
	}

    # Create a new question.
    if (!$id) {
        $dbh->do(q{
            INSERT INTO product.question (item, label, spec)  VALUES (?, ?, ?)
        }, undef, $item, $name, $spec);

        $id = $dbh->last_insert_id('', 'product', 'question', 'id');

        # New questions invalidate the old matrix (though we could add the
        # questions anwers to all answer sets and copy the assignments if we
        # wanted).
        delete_item_matrix($dbh, $item); 
    }
    else {
        # Update the question.
        $dbh->do(q{
            UPDATE product.question SET label = ? WHERE item = ? AND id = ?
        }, undef, $name, $item, $id);
    }

    # Update/delete any existing answers.
    if ($r->param('answer')) {
        my $delete = $dbh->prepare(q{
            DELETE FROM product.answer WHERE id = ?
        });
        my $update = $dbh->prepare(q{
            UPDATE product.answer SET label = ?, sort = ?, value = ? WHERE id = ?
        });

        for my $answer ($r->param('answer')) {
            if ($r->param("del-$answer")) { 
                $delete->execute($answer);
            }
            else {
                my $label = $r->param("label-$answer");

                my $sort  = $r->param("sort-$answer");
                   $sort  =~ tr/0-9//cd;
				my $spec = $r->param("value-$answer");

                $update->execute($label, $sort || 0, $spec, $answer);
            }
        }
    }

    # Add any new answers.
    if ($r->param('label')) {
        my $insert = $dbh->prepare(q{
            INSERT INTO product.answer (question, label, sort, value) VALUES (?, ?, ?, ?)
        });

        my @label = $r->param('label');
        my @sort  = $r->param('sort');
		my @value = $r->param('value');

        for my $i (0 .. $#label) {
            $insert->execute($id, $label[$i], $sort[$i] || 0, $value[$i] || 0) 
                if $label[$i];
        }
    }

    $dbh->commit;

    # Send them back from whence they came.
    $r->headers_out->{Location} = "question?item=$item;id=$id";
    $r->status(HTTP_MOVED_TEMPORARILY);
    return OK;
}


# List the predefined projects in the system as a quick reference.
sub projects {
    my $r = shift;
    my $t = shift;

    my $dbh = $r->pnotes('dbh');

    # Allow a basic search/filter of the list by project name.
    my $filter = '';
    if ($r->param('name')) {
        $filter = 'AND ' . join ' OR ', 
            map { 'strprojectreference ~* ' . $dbh->quote($_) }
                split / /, $r->param('name');
    }

    # Get all the predefined projects.
    my $projects = $dbh->selectall_arrayref(qq{
        SELECT lngprojectindex     AS id, 
               strprojectreference AS name
        FROM tbl_projects
        WHERE strstatus = 'predefined'
              $filter
    }, { Slice => {} });

    # Output the template.
    $r->content_type('text/html; charset=utf-8');
    $t->{file} = 'admin/predefined/projects.html';

    print $t->process(
        title     => 'Predefined Projects',
        projects  => $projects,
    );

    return OK;
}


# Sets the sort field of a number of records to 0..n in the order given.
sub sort_order {
    my ($dbh, $table, @ids) = @_;

    $table = $dbh->quote_identifier($table);

    my $sth = $dbh->prepare(qq{ 
        UPDATE $table SET sort = ? WHERE id = ?
    });

    my $i = 0;
    for my $id (@ids) {
        $sth->execute($i, $id);
        $i++;
    }
    
    return $i; # IDs processed
}

1;
