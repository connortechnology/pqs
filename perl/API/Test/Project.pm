package Test::Project;
use strict;
use warnings;

use Test::Builder;
use Test::Deep;
use Project::Pricing;
use List::Util qw(sum);

my $Test = Test::Builder->new(); # Singleton

our @ISA = qw(Exporter);
our @EXPORT = qw(is_pricing cmp_pricing cmp_page_to_pricing);


# Validate pricing structure.
{
    # Valid unsigned integer.
    my $is_uint = re('^\d+$');

    # Makes a test condition optional (undef means don't test).
    my $opt = sub {
        my $func = shift;

        return sub {
            my $str = shift;

            return 1 if !defined $str;

            $func->($str);
        }
    };

    # A valid price looks like ex. '352.52'.
    my $price = sub {
        my $str = shift;

        return (0, "Price missing.") unless defined $str;
       
        return ($str =~ /\d+\.\d\d/) ? 1
                                     : (0, "Invalid price ($str).");
    };

    # An optional price must be undefined or a valid price.
    my $opt_price = sub {
        my $str = shift;
        
        return 1 if !defined $str;

        return $price->($str);
    };

    # The second and third prices are optional.
    my $prices = [ code($price), code($opt->($price)), code($opt->($price)) ];

    # The full pricing structure.
    my $structure = {
        quantity => [ $is_uint, $is_uint, $is_uint ],
        services => array_each({
                name => ignore(),
                prices => $prices,
            }),
        stock => $prices,
        total => $prices,
    };

    # Is the given pricing structure a valid one?
    sub is_pricing {
        my ($pricing) = @_;
        return cmp_deeply($pricing, $structure, "valid structure");
    }
}

# Compare two pricing structures.
sub cmp_pricing {
    my ($pricing, $priced) = @_;

    # Compare the service, stock, and total prices (between this run and stored).
    cmp_deeply($pricing->{quantity}, $priced->{quantity}, "quantities match");
    cmp_deeply(
        $pricing->{services}, 
        bag(@{ $priced->{services} }), # Sort order doesn't concern us.
        "service pricing matches");

    cmp_deeply($pricing->{stock}, $priced->{stock}, "stock prices match");
    cmp_deeply($pricing->{total}, $priced->{total}, "total prices match");


    # Check that the sum of the service pricing equals the total for each qty.
    for my $i (0..2) {
        if ($pricing->{quantity}[$i]) {
            $Test->cmp_ok( 
                _add_price($pricing, $i), '==', $pricing->{total}[$i],
                "q$i : sum(services) + stock == total" );
        }
        else {
            $Test->ok(1, "q$i : No quantity to price");
        }
    }

}

# Totals the service and stock pricing (internal).
sub _add_price {
    my ($pricing, $i) = @_;

    return sum(map { $_->{prices}[$i] } @{$pricing->{services}})
         + $pricing->{stock}[$i]
}


sub cmp_page_to_pricing {
    my ($html, $priced) = @_;
    my $p = Project::Pricing->new($html);

 	ins($priced, $p);	
    return cmp_pricing($p->as_href, $priced);
}

sub ins {

	my ($priced, $p) = @_;
print STDERR "INSERT REF:" , $p->as_href->{id} , "-\n";

	use DBI;
	# Connect to the template database.
	my $t = DBI->connect('dbi:Pg:dbname=auto_test;', 'postgres', '', {
    	AutoCommit => 0,
    	RaiseError => 1,
	}) or die DBI->errstr;


	my @data = (@{$priced->{quantity}}, @{$priced->{stock}}, 
                @{$priced->{total}},    $p->as_href->{id} ); 

	$t->do(q{
		INSERT INTO a  values ( nextval('seq_a'), ?,?,?, ?,?,?, ?,?,?, ? )
	}, undef, @data );

	my $id = scalar $t->selectrow_array(q{
		Select currval('seq_a');
	});

	map {
		$t->do(q{
			INSERT INTO p values ( ?, ?, ?,?,? );
		}, undef, $id, $_->{name},@{$_->{prices}} )
	} @{$priced->{services}};

	map {
		$t->do(q{
			INSERT INTO r values ( ?, ?, ?,?,? );
		}, undef, $id, $_->{name},@{$_->{prices}} )
	} @{$p->as_href->{services}};

	$t->commit;
	$t->disconnect;
	
}

1;

__DATA__
my $pricing = { 
      quantity => [5000, 0, 0],
      services => [
          { name => 'Proofs', prices => ['46.00', undef, undef] }, 
          { name => 'Brochures - Sheetfed Offset Press', prices => ['142.00', undef, undef] }, 
          { name => 'Folding', prices => ['104.00', undef, undef] }, 
          { name => 'Cutting', prices => ['33.00', undef, undef] }, 
          { name => 'Cartons', prices => ['2.00', undef, undef] }
      ], 
      stock => ['42.00', undef, undef], 
      total => ['369.00', undef, undef] };


my $priced = { 
      quantity => [5000, 0, 0],
      services => [
          { name => 'Proofs', prices => ['46.00', undef, undef] }, 
          { name => 'Folding', prices => ['104.00', undef, undef] }, 
          { name => 'Cutting', prices => ['33.00', undef, undef] }, 
          { name => 'Cartons', prices => ['2.00', undef, undef] },
          { name => 'Brochures - Sheetfed Offset Press', prices => ['142.00', undef, undef] }, 
      ], 
      stock => ['42.00', undef, undef], 
      total => ['369.00', undef, undef] };
