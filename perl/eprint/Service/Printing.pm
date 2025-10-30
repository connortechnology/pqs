package eprint::Service::Printing;
use strict;
use warnings;
no warnings qw(uninitialized);

use POSIX qw(ceil);

use eprint::project       qw(:common :multipage template_service_types);
use eprint::service       qw(:common);
use eprint::print_project qw(insert_service delete_service);

use eprint::Service::Printing::Constants qw(:spread_types);
use eprint::Service::Printing::Display   qw(display template_sizes);
use eprint::Service::Printing::Validate  qw(munge);
use eprint::Service::Printing::Price     qw(calc count_completed_spreads signatures_of_type);

require openprint;

sub necessary {
    my ($log, $dbh, $pid, $service_type) = @_;

    # Printing is currently always needed unless we're checking out a
    # pre-printed project.
    return get_type($log, $dbh, $pid) ne 'InventoryCheckOut';
}


sub restore {
    my ($dbh, $pid, $sid, $service_type, $specs) = @_;

    # Bleeds are stored as a serialised list in the database *sigh*.
    $specs->{bleed_sides} = defined $specs->{bleed_sides}
        ? [ split(q{,}, $specs->{bleed_sides}) ] : [];

    # The versions are stored against 1NF as a flattened pair list.
    if ($specs->{version_quantities}) {
        my %versions = split ',', $specs->{version_quantities};

        $specs->{mv_name} = [ keys %versions ];
        $specs->{mv_qty}  = [ values %versions ];
		$specs->{versions} = \%versions;
    }

    return $specs;
}

sub store {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

    # Special case for bleeds, stringify selected bleed sides.        
    $specs->{bleed_sides} = defined $specs->{bleed_sides} 
        ? join(',', @{ $specs->{bleed_sides} }) : undef;

	print STDERR "STORE FOR Printing Servcie: PID: $pid SID: $sid \n";
    # Very, very simple multi-version input processing.
    if ($specs->{is_mv}) {
	print STDERR "STORE FOR Printing Servcie: START MV \n";
        my @name  = @{ $specs->{mv_name} } if $specs->{mv_name};
        my @qty   = @{ $specs->{mv_qty}  } if $specs->{mv_qty};
        my $total = (get_quantities($log, $dbh, $pid))[0];

        my (@versions, @quantities);

        # For now mirror the JS precisely. Note: Multiple labels of the
        # same name are allowed and treated as different versions.
        for my $i (0 .. $#qty) {
          next if ! $qty[$i];
          my $name    = $name[$i];
          my $qty     = int($qty[$i]);

          next unless $qty > 0;

          my $percent = ($qty / $total) * 100;

          if ($name and $percent and ceil($percent) > 0) {
            push @versions,   $name => $percent;
            push @quantities, $name => $qty;
          }
        }
		print STDERR "STORE FOR Printing Servcie: START MV @versions \n";
        $specs->{versions}           = join(',', @versions);
        $specs->{version_quantities} = join(',', @quantities); # For UI

		$specs->{s0_black_mv} = 'on' if ref $specs->{s0_black_mv} eq 'ARRAY';
		$specs->{s1_black_mv} = 'on' if ref $specs->{s1_black_mv} eq 'ARRAY';
		

    }

    return $specs;
}


sub preaction {
    my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

    # Only single page templates currently changes defaults of other services.
    return if is_multipage($log, $dbh, $pid);

    my $template = get_template($log, $dbh, $pid);

    # If we're changing our template we need to reset the specs of any old
    # service types so we don't have partially incorrect specs left around,
    # and we have to insert any project services here as later stages respect
    # if the user has removed a SUGGESTED service and don't re-add it. TODO:
    # Preserve default specs as inserted by insert_service().
    if ($template ne $specs->{template}) {

        my %template = template_service_types($log, $dbh, $pid);
        if (%template) {
            my @names = join ',', map { $dbh->quote($_) } keys %template;
            $dbh->do(qq{
                DELETE FROM tbl_service_specifications
                WHERE lngprojectindex = ?
                  AND strname !~ '^txtQuantity[1-3]'
                  AND lngserviceindex IN (
                          SELECT lngserviceindex
                          FROM tbl_project_contents
                          WHERE strservicetype IN (@names) )
            }, undef, $pid);
        }

        # Change the template over to the new one.
        insert_service_spec($log, $dbh, $pid, $sid, template => $specs->{template});

        # Now insert all the template project services if they don't already
        # exist. We'll let auto_calculation later on handle all the need
        # levels, etc.
        %template = template_service_types($log, $dbh, $pid);

        for my $name (keys %template) {
            my $sid = check_for_service($log, $dbh, $pid, $name);

            unless ($sid) {
                $sid = insert_service($log, $dbh, $pid, $name, {
                    user_requested => 0,
                    need_level     => $template{$name}{required},
                });
            }

            # If any template specifications are present for this service we
            # should insert them now.
            if (exists $template{$name}{specs}) {
                insert_service_specs(
                    $log, $dbh, $pid, $sid, %{ $template{$name}{specs} }
                );
            }
        }

        # As we've changed a bunch of project services and specs out from
        # under the user we'll reset their removal statuses to indicate they
        # should check it over again before removing it again or not.
        $dbh->do(q{ UPDATE tbl_project_contents
                    SET ysnremoved = FALSE
                    WHERE ysnremoved = TRUE
                      AND lngprojectindex = ?
        }, undef, $pid);
    }

    return 1;
}


# *** Should screen surfaces be checked like signatures?

sub action {
  my ($log, $dbh, $pid, $sid, $service_type, $specs) = @_;

  return unless is_multipage($log, $dbh, $pid) && get_press_type($log, $dbh, $pid) ne 'screen';

  my $book        = check_for_service($log, $dbh, $pid, 'Book');
  my $spread_type = $specs->{txtSignatureType} // COVER;
  $openprint::log->debug("Spread type in action: $spread_type");

  print STDERR "Invalid multipage project $pid book:$book spread type: $spread_type\n" unless $book && $spread_type;


  # If we're cover spreads there can only be one of us so we're done.
  return if $spread_type eq COVER;

  # PERFECT BOUND COVER SPREAD
  #
  # If we're creating a perfect bound book the cover spread needs to be
  # adjusted whenever any interior (includes gate folded) spread change.
  if (get_bindery_type($log, $dbh, $pid) eq 'PerfectBinding') {
    my $cover = signatures_of_type($log, $dbh, $pid, COVER);

    # Get the cover signature and check it's flat_width.
    if ($sid != $cover) {

      my $width   = get_specifications($log, $dbh, $pid, $book, 'final_width');
      my $spine   = get_finished_calliper($log, $dbh, {}, $pid);
      my $current = get_specifications($log, $dbh, $pid, $cover, 'txtSpreadWidth');

      $width = sprintf "%.3f", $width + $spine + $width;

      # If it's different from the calculated dimenion adjust the spec
      # and reset it to uncalculated.
      if ($width != $current) {
        insert_service_spec($log, $dbh, $pid, $cover, 
          txtSpreadWidth => $width,
        );
        set_status($log, $dbh, $pid, 'uncalculated', $cover)
      }
    }
  }

  # SIGNATURES
  #
  # Get all signatures of our type (excluding us) and those not completed.
  my @signatures = grep { $_ != $sid } 
  signatures_of_type($log, $dbh, $pid, $spread_type);

  my @unfinished = grep { get_status($log, $dbh, $_) ne 'calculated' }
  @signatures;

  my $needed   = get_specifications($log, $dbh, $pid, $book, $spread_type);
  my $current  = count_completed_spreads($log, $dbh, $spread_type, $pid, $sid);
  my $provided = $specs->{spreads_in_group} * ($specs->{txtSignatureQuantity} || 1);

  $current += $provided;

  # Compare the current total number of spreads we've defined against those
  # needed according to our parent book service.
  if ($current > $needed) {
    $openprint::log->debug("Have more sigs than needed $current > $needed");
    # We have too many signatures. Remove everyone but us.
    delete_service($log, $dbh, $pid, $_) for @signatures;

    #insert_signature($log, $dbh, $pid, $book, $sid, $specs) if $provided < $needed;

    $log->warn("Too many spreads in p:$book while processing s:$sid\n");
  } elsif ($current < $needed) {
    # We still need signatures, add a new one unless another unfinished
    # one already exists.
    insert_signature($log, $dbh, $pid, $book, $sid, $specs) unless @unfinished;
  } else {
    # Just right. We can remove any unfinished signatures there might be.
    delete_service($log, $dbh, $pid, $_) for @unfinished;
  }

  return $specs;
}

sub insert_signature {
    my ($log, $dbh, $pid, $book, $template, $specs) = @_;

    my @fields = qw( txtSignatureType txtSignatureSize 
                     txtSpreadWidth txtSpreadHeight );
    my %signature;
    @signature{@fields} = @$specs{@fields};

    # Insert a new signatue
    my $sid = insert_service($log, $dbh, $pid, 'Printing', { user_requested => 1 }, \%signature);

    # Update the signature number TODO Get rid of this legacy nonsense.
    insert_service_spec($log, $dbh, $pid, $sid, SignatureIndex => $sid);


    # Only copy the user specified fields and no overrides.
    $dbh->do(qq{
        INSERT INTO tbl_service_specifications 
            (lngprojectindex, lngserviceindex, strname, strvalue, ui_spec)
            ( SELECT lngprojectindex, $sid, strname, strvalue, ui_spec
              FROM tbl_service_specifications
              WHERE lngserviceindex = ?
                AND ui_spec = true 
                AND strname !~ '^override'
                AND strname NOT IN ( 'press', 'runstyle', 'substrate', 
                                     'spreads_in_group', 'spreads', 'forms' )
                AND strname !~ '^txtSignatureQ')
    }, undef, $template);

    my $ptd = $dbh->selectall_hashref(q{ SELECT strfieldname as name, strdefaultvalue as value FROM tbl_projecttype_defaults WHERE lngprojecttypeindex IS NULL }, 'name');

    my %defaults;
    map { $defaults{$_} = $ptd->{$_}{value} } keys %$ptd;
    insert_service_specs($log, $dbh, $pid, $sid, %defaults);

    # If there's a numbered description, update to next.
    if ($specs->{txtServiceDescription} =~ /(\d+)$/) {
        my $count = $1 + 1;

        my $name = $specs->{txtServiceDescription};
           $name =~ s/\d+$/$count/;

        insert_service_spec($log, $dbh, $pid, $sid, txtServiceDescription => $name);
    }

    # Override the press to the same as other signatures of this type.
    # This is done to ensure a consistant look and registration of the
    # final project.
    insert_service_spec($log, $dbh, $pid, $sid, press          => $specs->{press}, undef, 1);
    insert_service_spec($log, $dbh, $pid, $sid, override_press => 1,               undef, 1);


    # 'DETAILED' MODE
    #
    # 'Detailed' mode sets a kludgy flag to stop calculation until the
    # display() function removes the flag (meaning a user has seen it).
    if ($specs->{spreads} || $specs->{forms}) {
        insert_service_spec($log, $dbh, $pid, $sid, needs_view => 1, undef, 1);
    }

    return $sid;
}

1;
