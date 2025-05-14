package PQS::Equipment;
use strict;
use warnings;

use Carp;
use Scalar::Util qw(dualvar looks_like_number);
use List::Util qw(first);
use Tie::Hash::Equipment;

use base qw(Exporter);
our @EXPORT    = qw(get_equipment);
our @EXPORT_OK = qw(get_equipment create_range_lookup);

# Return a tied hash representing all the attribute of the equipment. This is
# primarily a transitional step to segue between the hashes of old the system
# and moving towards OO. The hash normalizes keys before lookup -- lower
# casing everything and replacing spaces with underscore, stops modification,
# and provides subs for range lookups. All basic equipement attributes an
# 'specifications' are avaliable.
sub get_equipment {
  my ($dbh, $id) = @_;

  croak "Equipment ID not provided." unless defined $id && looks_like_number($id);

  # All equipment will have the primary fields in it's hash.
  my $sth = $dbh->prepare_cached(q{
    SELECT e.lngindex AS id,        e.strid          AS reference, 
    e.strname  AS name,      e.strdescription AS description,
    t.lngindex AS type_id,   e.strtype        AS type_ref,
    t.strname  AS type_name, e.strsupplier    AS supplier
    FROM tbl_equipment e, tbl_equipment_type t
    WHERE e.strtype = t.strid
    AND e.lngindex = ?
    });
  my $equip = $dbh->selectrow_hashref($sth, {}, $id);

  croak "Equipment ($id) does not exists." unless $equip;
  $openprint::log->debug(Data::Dumper::Dumper($equip));

  # Create a dualvar of the numeric and string equipment type for ease.
  $equip->{type} = dualvar $equip->{type_id}, $equip->{type_ref};

  # Get the equipments specs normalized to all lower case with spaces
  # replaced with underscores.
  my $specs = $dbh->prepare_cached(q{
    SELECT replace(lower(strname), ' ', '_'), strvalue, dblmin, dblmax 
    FROM tbl_equipment_specifications
    WHERE lngequipmentindex = ?
    });
  $specs->execute($id);
  my ($name, $value, $min, $max);
  $specs->bind_columns(\$name, \$value, \$min, \$max);

  my %ranged;
  while ($specs->fetch) {
    # If min or max is defined we have a ranged spec. 
    if (defined $min or defined $max) {
      $equip->{$name} = [] unless exists $equip->{$name};

      # Push a range onto the list (we'll sort them later).
      push @{ $equip->{$name} }, [$min, $max, $value];

      # Keep a unique list of the ranged ones so we can convert their
      # data to lookup functions.
      $ranged{$name} = undef;
    }
    # Or it's just an attribute.
    else { 
      # We'll map those horrible 'Y' or 'N' attributes to boolean here.
      # Anything that's actually supposed to equal that is out of luck.
      # TODO Create an overloaded (tied?) var that allows the yes/no
      # string but provides the correct bool return.
      $equip->{$name} = ! defined $value ? undef
      : $value eq 'Y'    ? 1
      : $value eq 'N'    ? 0
      :                    $value; 
    }
  }

  # Now that our ranged specs have all their data, we need to turn them into
  # functions that can do lookups on their data.
  for my $name (keys %ranged) {
    $equip->{$name} = create_range_lookup( @{ $equip->{$name} } );
  }

  # A single piece of equipment can perform multiple services. We'll add a
  # list of services the equipment does perform.
  my $services = $dbh->prepare_cached(q{
    SELECT t.lngindex, t.strid 
    FROM service_type_equipment s, tbl_service_types t
    WHERE t.lngindex = s.service_type
    AND s.equipment = ?
    });

  die "'services' is a reserved key (used erroneously by equipment $id)" if exists $equip->{services};

  $equip->{services} = [ map { dualvar $_->[0], $_->[1] } @{ $dbh->selectall_arrayref($services, undef, $id) } ];

  $equip->{invalid_substrates} = $dbh->selectcol_arrayref(q{ SELECT paper FROM equipment_paper_exclusion 
    WHERE equipment = ?
    },undef,$equip->{id});

  # The interface we'll provide will be the standard hash for legacy
  # reasons; however, we'll impose a readonly contraint, normalize any input
  # hash keys to a lowercase and space to underscore name, and make
  # auto-vivification of keys throw an exception.
  my %equipment;
  tie %equipment, 'Tie::Hash::Equipment', $equip;

  return \%equipment;
}

# Creates a lookup function over a (unbounded or bounded) range that returns
# the value associated with the range the supplied number falls into. TODO
# Verify the range and create a better internal format than just copying the
# databases bad format. TODO Die on bad input or unfound lookups
sub create_range_lookup {
    # Sort the supplied ranges by ascending min value.
    my @ranges = sort {    defined $a->[0] <=> defined $b->[0] 
                        || $a->[0] <=> $b->[0] 
                      } @_;

    # A range is [ [min, max, value], ... ]
    return sub {
        my ($n) = @_; # Lookup number.

        my $match = first { 
            my ($min, $max) = @$_;
            (!defined $min || $n >= $min) && (!defined $max || $n <= $max);
        } @ranges;

        return unless $match;
        # croak "Value ($n) outside range bounds." unless $match;

        return $match->[-1]; # Last element is the value.
    };
}


1;
