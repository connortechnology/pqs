package eprint::equipment;
use strict;


use Carp;
use Scalar::Util qw(dualvar looks_like_number);
use List::Util qw(first);
use Tie::Hash::Equipment;
use sql ();

use base qw(Exporter);
our @EXPORT_OK = qw( get_name
                     get_type
                     equipment_fits
                     get_specification
                     get_specifications
                     get_units
                     get_index_by_id
                     load_specs
                     create_range_lookup
);
our %EXPORT_TAGS = ( common => [@EXPORT_OK] );

our %cache; # TEMP: To store localized caches of equipment specs.

# Given the equipment's ID return it's name.
sub get_name {
    my ($log, $dbh, $eid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT strname FROM tbl_equipment WHERE lngindex = ?
    });

    return scalar $dbh->selectrow_array($sth, undef, $eid);
}

sub bindery_imp {
	my ($imp_over, $specs) = @_;




        my $imp_width  = 0;
        my $imp_height = 0;
		my $up = 1;


		if ( $imp_over ) {
			$up =  $specs->{txtImposition1};
            $imp_width  = $$specs{"txtImageWidth1"};
            $imp_height = $$specs{"txtImageHeight1"};
		} else {
            $imp_width  = $$specs{"flat_width"};
            $imp_height = $$specs{"flat_height"};
		}

		return ($up, $imp_width, $imp_height);
}

# Given the equipment's ID return it's type.
sub get_type {
    my ($log, $dbh, $eid) = @_;

    return scalar $dbh->selectrow_array(q{
        SELECT strtype FROM tbl_equipment WHERE lngindex = ?
    }, undef, $eid);
}

# Get the string reference from the numeric ID.
sub get_id_by_index {
    my ($log, $dbh, $eid) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT strid FROM tbl_equipment WHERE lngindex = ?
    });

    return scalar $dbh->selectrow_array($sth, undef, $eid);
}

# Get the numeric ID from the string reference.
sub get_index_by_id {
    my ($log, $dbh, $ref) = @_;

    return scalar $dbh->selectrow_array(q{
        SELECT lngIndex FROM tbl_Equipment WHERE strID = ?
    }, undef, $ref);
}

# Creates a lookup function over a (unbounded or bounded) range that returns
# the value associated with the range the supplied number falls into. TODO
# Verify the range and create a better internal format than just copying the
# databases bad format. TODO Die on bad input or unfound lookups
sub create_range_lookup {
    # Sort the supplied ranges by ascending min value.
    my @ranges;
    {
        no warnings qw(uninitialized);
        @ranges = sort {    defined $a->[0] <=> defined $b->[0]
                         ||         $a->[0] <=> $b->[0]          } @_;
    }

    # A range is [ [min, max, value], ... ]
    return sub {
        my ($n) = @_; # Lookup number.
        my $match = first {
            my ($min, $max) = @$_;
            (!$min || $n >= $min) && (!$max || $n <= $max);
        } @ranges;

        return unless $match;
        # croak "Value ($n) outside range bounds." unless $match;

        return $match->[-1]; # Last element is the value.
    };
}

# Create a hash of equipment specs stored by equipment ID. Used to load the
# cache up with all the specs for a given equipment type. The whole loop
# section should be generalized between get_equipment, service::load_prices,
# and this.
sub load_specs {
    my ($dbh, $equipment_type) = @_;

    # Get the equipments specs normalized to all lower case with spaces
    # replaced with underscores.
    my $specs = $dbh->prepare_cached(q{
        SELECT e.lngindex, replace(lower(s.strname), ' ', '_'),
               s.strvalue, s.dblmin, s.dblmax
        FROM tbl_equipment_specifications s, tbl_equipment e
        WHERE e.lngindex = s.lngequipmentindex
          AND e.strtype = ?
    });
    $specs->execute($equipment_type);
    my ($id, $name, $value, $min, $max);
    $specs->bind_columns(\$id, \$name, \$value, \$min, \$max);

    my (%equip, %ranged);
    while ($specs->fetch) {
        # If min or max is defined we have a ranged spec. 
        if (defined $min or defined $max) {
            $equip{$id}{$name} = [] unless exists $equip{$id}{$name};

            # Push a range onto the list (we'll sort them later).
            push @{ $equip{$id}{$name} }, [$min, $max, $value];

            # Keep a unique list of the ranged ones so we can convert their
            # data to lookup functions.
            $ranged{"$id~$name"} = undef;
        }
        # Or it's just an attribute.
        else { 
            $equip{$id}{$name} = $value; 
        }
    }

    # Now that our ranged specs have all their data, we need to turn them into
    # functions that can do lookups on their data.
    for my $key (keys %ranged) {
        my ($id, $name) = split /~/, $key;
        $equip{$id}{$name} = create_range_lookup( @{ $equip{$id}{$name} } );
    }
   
    return %equip;
}

sub cache_lookup {
    my ($eid, $range, @specs) = @_;

    # Normalize the names to lc spaces to underscore.
    my @names = map { tr/A-Z /a-z_/; $_ } @specs;

    # If we're only looking up one specification we can do range lookups.
    if (@names == 1) {
        my $name = $names[0];

        # If the equipment or service doesn't exist the can't be any pirce.
        return unless exists $cache{$eid}{$name};
        
        my $spec = $cache{$eid}{$name};

        if (ref $spec eq 'CODE') {
            # If the price is a coderef (for range lookup) and the user didn't
            # pass us a lookup value we can't do anything.
            return unless defined $range && looks_like_number($range);

            # Errors aren't expected from the legacy lookup, so we won't.
            eval    { $spec = $spec->($range); };
            if ($@) { return; }
        }
        return $spec;
    }
    # Otherwise we're doing a bulk lookup and we'll return a hash of lookup
    # keys and found values. Any ranged specifications will return undef.
    else {
        # Create a new hash of the wanted specs, anything ranged becomes undef
        # as this funcion doesn't do range lookups.
        my %equip;
        @equip{ @specs } = map { ref $_ eq 'CODE' ? undef : $_ }
                              @{ $cache{$eid} }{ @names };

        return @equip{ @names };
    }
    return; # Should never reach here.
}


# If no specific specification names are requested, get them all.
sub get_specifications {
    my ($log, $dbh, $eid, @specs) = @_;

    # Basic sanity check, improve on this.
    croak "Equipment index must be supplied" unless $eid;

    # Equipment (among others) is weird in having two keys that are used
    # interchangably as the primary key. If the string key is passed convert
    # it to the numeric one.
    $eid = ( $eid =~ /^\d+$/ ) ? $eid : get_index_by_id($log, $dbh, $eid);

    # TEMP: Get from package cache if it's been populated.
    return cache_lookup($eid, undef, @specs) 
        if %cache && exists $cache{$eid} && @specs;

    my $sql = q{
        SELECT strName, strValue
        FROM tbl_Equipment_Specifications
        WHERE lngEquipmentIndex = ?
    };

    if (scalar @specs) {
        my $placeholders = join ', ', ('?') x @specs;

        # By calling lower() and replace() on the specification name we use
        # the functional index on it and reduce name lookup errors.
        $sql .= "AND lower(replace(strName, ' ', '')) IN ( $placeholders )";
    }

    # Remove all spaces and lowercase the specification name given so we to
    # avoid lookup errors in our ever so fun hash style table.
    @specs = map { tr/A-Z /a-z/d; $_ } @specs if @specs;

    my $sth = $dbh->prepare($sql);
    $sth->execute($eid, @specs);   # @specs will be () if none passed.

    my                (  $name,  $value );
    $sth->bind_columns( \$name, \$value );

    my %equip;
    $equip{$name} = $value while ($sth->fetch);

    # Neither hashes nor IN() guarantee ordering. Quick fix that should
    # guarantee proper ordering until a better system can be found.
    my %order;
    if (@specs) {
        for (keys %equip) {
            my $spec = $_;
            tr/A-Z /a-z/d;

            $order{ $_ } = $spec;
        }
    }

    # If a specification list was given only a value list is expected,
    # otherwise return the full hash.
    return (@specs) ? @equip{ @order{ @specs } } : %equip;
}

# Duke: This procedure will get units based on a service and a piece of
# equipment using this data we will be able to switch our processing logic for
# any service/equipment pair.
sub get_units {
    my ($log, $dbh, $service, $equipment, $variable) = @_;

    $equipment = get_index_by_id($log, $dbh, $equipment) unless $equipment+0;

    # We should only be returning one item, but if there are duplicates we
    # will only care about the first one anyway.  and the above only caring
    # about the first one made a nasty bug since we get multiple rows from
    # different pricelists that can be different changing it - Duke
    return scalar $dbh->selectrow_array(qq{
        SELECT p.strunits
        FROM tbl_service_prices p, tbl_services s, tbl_customer c
        WHERE p.lngserviceindex = s.lngindex
          AND p.lnglistindex = c.lngpricelist
          AND s.strid             = ?
          AND p.lngequipmentindex = ?
          AND c.lngcustomerid     = ?
    }, undef, $service, $equipment, $variable->{cust_id});
}

# Given a specification to lookup, an optional range, and the equipment index
# this returns the specification's value.
sub get_specification {
    my ($log,
        $dbh,
        $name,  # Specification string ID
        $range, # Value to check if in range
        $eid,   # Equipment ID
    ) = @_;

    # Basic sanity check, improve on this.
    croak "Equipment index must be supplied" unless $eid;

    # Equipment (among others) is weird in having two keys that are used
    # interchangably as the primary key. If the string key is passed convert
    # it to the numeric one.
    $eid = ( $eid =~ /^\d+$/ ) ? $eid : get_index_by_id($log, $dbh, $eid);

    # TEMP: Get from package cache if it's been populated.
    return cache_lookup($eid, $range, $name) 
        if %cache and exists $cache{$eid};

    # Remove all spaces and lowercase the specification name given so we to
    # avoid lookup errors in our ever so fun hash style table.
    $name =~ tr/A-Z /a-z/d;
    
    my @args = ($eid, $name);
    
    # By calling lower() and replace() on the specification name we use
    # the functional index on it and reduce name lookup errors.
    my $sql = qq{ SELECT strValue 
                  FROM tbl_Equipment_Specifications
                  WHERE lngEquipmentIndex = ?
                    AND lower(replace(strName, ' ', '')) = ?
        };
    if ($range > 0) {
        $sql .= qq{ AND (? >= dblMin OR dblMin isNull) 
                    AND (? <= dblMax OR dblMax isNull)
                  ORDER BY dblmin 
                  LIMIT 1
        };

        push @args, $range, $range;
    } 

    return scalar $dbh->selectrow_array($sql, undef, @args);
}

sub equipment_fits {
    my ( $log,    $dbh,                $eid, 
         $width,  $height,             $calliper, 
         $rotate, $min_width_override, $min_length_override 
     ) = @_;

use Data::Dumper;
print STDERR "EQUIPMENT FITS: ", Dumper(@_);
print STDERR "FITS 1\n";
    # If we haven't explicitly said we can't rotate the supplied dimensions
    # to try fitting the other way, we'll assume we can (legacy reasons).
    $rotate = 1 unless defined $rotate and $rotate == 0;

    # If the equipment type is manual then we are going to say
    # that the project will always fit.
    my $e_type = scalar $dbh->selectrow_array(q{
        SELECT strtype
        FROM tbl_equipment
        WHERE lngindex = ?
    }, undef, $eid);
	return 1 if ($e_type eq 'manual' or $e_type eq 'personalcomputer');

    # The equipment in question.
    my %equip = get_specifications( $log, $dbh, $eid );
    
    if (defined $min_width_override) {
        $equip{'Minimum Sheet Width'} = $min_width_override;
    }
    if (defined $min_length_override) {
        $equip{'Minimum Sheet Length'} = $min_length_override;
    }
print STDERR "FITS 2\n";
    # Check the supplied size agains the equipment.    
    if ((( 1*$width  < 1*$equip{'Minimum Sheet Width'} ) 
      or ( 1*$height < 1*$equip{'Minimum Sheet Length'}) 
      or ( 1*$width  > 1*$equip{'Maximum Sheet Width'} )
      or ( 1*$height > 1*$equip{'Maximum Sheet Length'}) )) 
    {
        $log->debug("Doesn't fit without rotation");

        # It didn't fit so try it rotated unless we aren't allowed.
        if (($rotate == 0
          or ( 1*$height < 1*$equip{'Minimum Sheet Width'} )
          or ( 1*$width  < 1*$equip{'Minimum Sheet Length'})
          or ( 1*$height > 1*$equip{'Maximum Sheet Width'} )
          or ( 1*$width  > 1*$equip{'Maximum Sheet Length'}) ))
        {
            return 0;
        }
    }
print STDERR "FITS 3\n";
    
    # If the width and height fit, check the depth.
    if ( $equip{'Minimum Calliper'} and 1*$calliper > 0 and 1*$calliper < 1*$equip{'Minimum Calliper'} ) {
        return 0;  
    }
    if ( $equip{'Maximum Calliper'} and 1*$calliper > 0 and 1*$calliper > 1*$equip{'Maximum Calliper'} ) {
        return 0;
    }
print STDERR "Equip: $eid FITS Project W: $width x H: $height on ", Dumper(\%equip); 
    # If we're here it fits.
    return 1;
}

1;

