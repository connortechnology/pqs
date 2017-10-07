package Project::Pricing;
use strict;
use warnings;

use Data::Dumper;
use HTML::TableContentParser;

# The cell positions of the needed pieces of data in the pricing table.
use constant {
    SERVICE => 0,
    Q1      => 1,
    Q2      => 2,
    Q3      => 3,
    STATUS  => 4,
};

#my $html = do { local $/ = undef; <DATA> };
#my $table = get_pricing_table($html);
#die Dumper $table;

#my $p = Project::Pricing->new($html);
#print Dumper $p->as_href;
#print $p->dump, $/;
#print $p->as_string;

sub new {
    my ($class, $html) = @_;

    my $table = get_pricing_table($html);
    my $ref   = get_ref($html);
print STDERR "\n REF: $ref \n";

    # Create a pricing structure from the project view page.
    return bless {
        pricing => {
            quantity => quantity($table),
            services => services($table),
            stock    => materials($table),
            total    => totals($table),
			id => $ref
        },
    }, $class;
}

sub as_href { return shift->{pricing} }

# Display the pricing structure as a formatted text table.
sub as_string {
    my $pricing = shift->{pricing};

    my $str = "\n";

    # List the quantities
    $str .= sprintf "%-40s %9d %9d %9d\n", '', @{$pricing->{quantity}};
    $str .= ('-' x 70) . $/;

    $str .= "SERVICES\n";

    no warnings qw(uninitialized);

    # List each service.
    for my $service (@{ $pricing->{services} }) {

        $str .= sprintf "%-40s %9.2f %9.2f %9.2f\n",
            "     $service->{name}",
            @{ $service->{prices} };
    }
    $str .= $/;

    # Materials
    $str .= sprintf "%-40s %9.2f %9.2f %9.2f\n", 'STOCK', @{$pricing->{stock}};

    # Grand total under a double line.
    $str .= ('=' x 70) . $/;
    $str .= sprintf "%-40s %9.2f %9.2f %9.2f\n", 'TOTAL', @{$pricing->{total}};

    return $str;
}

# Dump in a compact but readable form.
sub dump {
    my $pricing = shift->{pricing};

    no warnings qw(uninitialized);

    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 0;

    $_ = Dumper $pricing;

    # Ugly as hell but it works.
    s/(quantity|services|stock|total) =>/\n$1 =>/g;
    s/\[{/\[\n{/gs;
    s/{/{ /gs;
    s/]}(,)?/] }$1\n/gs;
    s/,/, /gs;
    s/{ name/    { name/gs;
    s/\n/\n    /gs;
    s/^/my \$priced = /;
    s/\s*$/;/s;

    return $_;
}

# Find the table in the given HTML.
sub get_pricing_table {
    my ($html) = @_;

    my $parser = HTML::TableContentParser->new();
    my $tables = $parser->parse($html);

    my @matches = grep { $_->{id} && $_->{id} eq 'service-pricing' } @$tables;

    die "No pricing tables found." unless @matches;

    die "More than one pricing table found." if @matches > 1;

    return $matches[0];
}
# Find the table in the given HTML.

sub get_ref {
    my ($html) = @_;

    my $parser = HTML::TableContentParser->new();
    my $tables = $parser->parse($html);


	my @matches = grep { $_->{rows}[0]->{cells}[0]{data} =~ 'Reference' } @$tables;

    die "No reference tables found." unless @matches;

    die "More than one reference table found." if @matches > 1;

	return $matches[0]->{rows}[0]->{cells}[1]{data};

}

# Get the pricing for all the services.
sub services {
    my ($table) = @_;

    my @pricing;
    for my $row (@{$table->{rows}}) {
        next unless $row->{cells}[Q1]
                 && $row->{cells}[Q1]{data};

        my $service = service_name($row->{cells}[SERVICE]{data});

        my @prices = map { clean_price(ref $_ ? $_->{data} : $_) } 
                        @{$row->{cells}}[Q1, Q2, Q3];

        # There can be multiple services called the same thing, so we'll form
        # an array as we see them.
        push @pricing, {name => $service, prices => \@prices}
            if $service && $prices[0];
    }

    die "No pricing found" unless @pricing;

    return \@pricing;
}

# Project quantities.
sub quantity {
    my ($table) = @_;

    return [ map { int(ref $_ ? $_->{data} : $_) }
                @{ $table->{headers} }[Q1, Q2, Q3] ];

}

# Get the pricing from a given row (ordinal).
sub get_prices_from_row {
    my ($table, $row) = @_;

    return [ map { clean_price(ref $_ ? $_->{data} : $_) }
                @{ $table->{rows}[$row]{cells} }[Q1, Q2, Q3] ];
}

sub totals    { get_prices_from_row(@_, -1) } # Project totals

# Material (stock) totals
sub materials { 
    my ($table) = @_;

    my $row = -4; # Standard location.

    # If there are multiple stocks we'll need to search for the stock price.
    unless (!$table->{rows}[$row]{cells}[0]{data} eq 'Stock') {
        undef $row;

        for my $i (0 .. $#{ @{ $table->{rows} } }) {
            $row = $i if $table->{rows}[$i]{cells}[0]{data} eq 'Stock';
        }

        return [undef, undef, undef] unless $row;
    }

    return get_prices_from_row(@_, $row) 
}


# Services names are in an anchor.
sub service_name {
    my $service = shift;
    
    return undef unless defined $service;

    $service =~ m/\&#183;\s*(?:<a[^>]+>\s*)?([^<]+)\s*(?:<)?/;
    $service = $1;

    return undef unless defined $service;

    $service =~ s/\s*$//s;
    $service =~ s/&#\d{3,4};/-/;

    return $service;
}


# Get only the float that is the price.
sub clean_price {
    my $price = shift;
    return undef unless defined $price;

    $price =~ m/(-?\d+\.\d\d)/;
    $price = $1;

    return undef unless defined $price;

    return ($price+0 == 0) ? undef : $price;
}


1;

__DATA__
<table id="service-pricing" class="project-current-view no-formatting">
	<col id="service" />
	<col id="qty1" />
	<col id="qty2" />
	<col id="qty3" />
	<col id="status" />
	<col id="changes" class="control" />

	<!-- SERVICES -->
	<thead>
		<tr class="title">
			<th style="border-left-width: 1px;">Services</th>
			<th style="text-align: right;">5000</th>
			<th style="text-align: right;">0</th>
			<th style="text-align: right;">0</th>

			<th style="text-align: right;">Status</th>
			<th class="control print-right-border" style="text-align: right; border-right-width: 1px;">Changes</th>
		</tr>
	</thead>

	<!-- Service pricing by category. -->
	<tbody>
			<tr class="category Prepress">
				<td style="font-weight: bold;">Prepress</td>
				<td></td>
				<td></td>
				<td></td>
				<td colspan="2"></td>
			</tr>

			<!-- Services in . -->				
			
            <tr class="service Proofs">
                <td> &#183; <a href="/service/proofs?pid=5000;sid=20003">Proofs</a> </td>

                <td style="text-align: right;">$ 105.00</td>
                <td style="text-align: right;"></td>
                <td style="text-align: right;"></td>
                <td class="calculated" style="text-align: right;">Calculated</td>
                <td class="control" style="text-align: right;">
                                <a href="/service/proofs?pid=5000;sid=20003">Edit</a>
                                 / 
                                <a href="/main/proj/dispatch.html?action=remove;pid=5000;sid=20003">Supply</a>
                </td>
            </tr>
			<tr class="category Printing">
				<td style="font-weight: bold;">Printing</td>

				<td></td>
				<td></td>
				<td></td>
				<td colspan="2"></td>
			</tr>

			<!-- Services in . -->				
			
				<tr class="service Printing">
					<td> &#183; <a href="/service/printing?pid=5000;sid=20000">Posters &#8211; Sheetfed Offset Press</a></td>

					<td style="text-align: right;">$ 723.00</td>

					<td style="text-align: right;"></td>
					<td style="text-align: right;"></td>
					
					<td class="calculated" style="text-align: right;">
							Calculated
					</td>

					<td class="control" style="text-align: right;">
									<a href="/service/printing?pid=5000;sid=20000">Edit</a>
									 / 
							
									<a href="/main/proj/proj_printer_summ_price_breakdown.html?ProjectIndex=5000;ServiceIndex=20000#chosen">+</a>
					</td>
				</tr>
			<tr class="category Finishing">
				<td style="font-weight: bold;">
						Finishing 		
				</td>
				<td></td>
				<td></td>
				<td></td>
				<td colspan="2"></td>
			</tr>
			<!-- Services in . -->				
				<tr class="service Cutting">
					<td> &#183; 
							<a href="/service/cutting?pid=5000;sid=20004">Cutting</a>
					</td>
					<td style="text-align: right;">$ 60.00</td>
					<td style="text-align: right;"></td>
					<td style="text-align: right;"></td>
					<td class="calculated" style="text-align: right;">
							Calculated
					</td>
					<td class="control" style="text-align: right;">
									<a href="/service/cutting?pid=5000;sid=20004">Edit</a>
									 / 
									<a href="/main/proj/dispatch.html?action=remove;pid=5000;sid=20004">Supply</a>
					</td>
				</tr>
			<tr class="category Packaging">
				<td style="font-weight: bold;">
						Packaging 		
				</td>
				<td></td>
				<td></td>
				<td></td>
				<td colspan="2"></td>
			</tr>
			<!-- Services in . -->				
				<tr class="service PlainCartons">
					<td> &#183; 
							<a href="/service/plaincartons?pid=5000;sid=20001">Cartons</a>
					</td>
					<td style="text-align: right;">$ 28.00</td>
					<td style="text-align: right;"></td>
					<td style="text-align: right;"></td>
					<td class="calculated" style="text-align: right;">
							Calculated
					</td>
					<td class="control" style="text-align: right;">
									<a href="/service/plaincartons?pid=5000;sid=20001">Edit</a>
									 / 
									<a href="/main/proj/dispatch.html?action=remove;pid=5000;sid=20001">Remove</a>
					</td>
				</tr>
		<!-- Admin/Employee "Add Line Item" Contols. -->
			<form name="additem" method="post" action="/main/proj/dispatch.html">
				<tr class="control">
					<td><input name="item_name" size="20" class="smbox" /></td>
					<td><input name="price-1" size="9"  class="smbox" /></td>
					<td></td>
					<td></td>
					<td colspan="2">
							<input type="hidden" name="pid" value="5000" />
							<input type="hidden" name="action" value="add_line_item" />
							<input type="submit" class="button" id="add-line-item" value="Add Line Item" />
					</td>
				</tr>
			</form>
		<!-- MATERIALS -->
		<tr class="title">
			<th colspan="6" style="border-width: 1px;">Materials</th>
		</tr>
				<!-- Stock pricing seperated from the form it belongs to (if the flag was set) -->
				<tr class="total">
					<th>Stock</th>
					<td>$ 820.00</td>
					<td>$ 0.00</td>
					<td>$ 0.00</td>
				</tr>
			<!-- Stock information. -->
				<tr>
					<td style="text-align: left; padding-left: 2em;">Text - House Stock - Gloss 80lb - Text (25&#8243; &#215; 38&#8243;)</td>
						<td style="text-align: right;">5600</td>
						<td style="text-align: right;"></td>
						<td style="text-align: right;"></td>
				</tr>
		<!-- TOTALS -->
			<tr class="total unit">
				<th>Project Unit Price:</th>
				<td>$ 0.35</td>
				<td></td>
				<td></td>
			</tr>
			<tr class="total grand">
				<th>Project Total:</th>
				<td>$ 1736.00</td>
				<td></td>
				<td></td>
			</tr>
	</tbody>
</table>
