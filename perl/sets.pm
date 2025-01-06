use strict;
package sets;

sub isin {

	if ( ! defined $_[0] ) {
		my ( $caller, undef, $line ) = caller;
Carp::cluck("undefined needle in isin from $caller:$line");
		return;
	}

	my %h;
    # Takes in a variable, and an array, and checks the array element by
    # element to see if the variable exists inside the array.
	if ( @_ == 2 ) {
#$openprint::log->debug( 'REF' . ref $thing );
		if ( ref $_[1] eq 'ARRAY' ) {

			#%h = %{ { map { $_ => 1 } @{$_[1]} } };
			
			foreach (@{$_[1]}) {
				return 1 if (
					((!defined $_[0]) and !defined($_))
					or 
					( defined($_) and defined($_[0]) and ($_ eq $_[0]) ) 
					);
			} # end foeach
			return 1 if $h{$_[0]};
		} else {
			return 1 if $_[1] eq $_[0];
		} # end if
	} elsif ( @_ > 2 ) {
		my $var = shift @_;
		foreach (@_) {
			return 1 if $_ eq $var;
		} # end foreach
	} # end if
    return 0;
} # end sub isin

sub isin_regx {
# Takes in a variable, and an array, and checks the array element by
# element to see if the variable exists inside the array.

	my $var = shift;
	foreach my $value (@_) {
		$value =~ s/\\\\/\\/g;
		if ( $var =~ /^($value)$/ ) {
#$openprint::log->debug("isin_regx: matched $value");
			return 1;
		#} else {
#$openprint::log->debug("isin_regx: not matched ($var) ($value)");

		} # end if
	} # end foeach
	return 0;

} # end sub inin_regx

sub ordered_union {
	my %hash;
	my @results;
	foreach ( @_ ) {
		if ( ! $hash{$_} ) {
			push @results, $_;
			$hash{$_} = !undef;
		}
	}
	return @results;
}

sub union {
	return keys %{{ map { $_ => 1 } @_ }};
} # end sub union

sub object_union {
	return values %{{ map { $_->id() => $_ } @_ }};
} # end sub union

sub contains {
	my ( $setA, $setB ) = @_;

	my @contains;

	foreach ( @{$setA} ) {
		if ( isin( $_, $setB ) ) {
			push @contains, $_;
		} # end if
	} # end foreach
	return @contains;
} # end sub contains

sub intersection {
	my %elements;
	my $count = 2;
	my @result = ();

	foreach ( @_ ) {
		$elements{$_} += 1;
		if ( $elements{$_} > $count ) {
			$count = $elements{$_};
		} # end if
	} # end foreach

	foreach ( keys %elements ) {
		if ( $elements{$_} == $count ) {
			push @result, $_;
		} # end if
	} # end foreach
	return @result;
};

sub xor {
	my %elements;
	my @result = ();
	foreach ( @_ ) {
		$elements{$_} += 1;
	} # end foreach
	foreach ( keys %elements ) {
		if ( $elements{$_} == 1 ) {
			push @result, $_;
		} # end if
	} # end foreach
	return @result;
}

# We do it this way to maintain ordering of the input array
sub exclude {
	my ( $exclude, $array ) = @_;
	if ( (! $array) or (! @{$array}) ) {
		return ();
	} # end if
	if ( (! $exclude) or (! @{$exclude}) ) {
		return @{$array};
	} # end if
	my @results;
	my %exclude = map { $_ => 1 } @{$exclude};
	foreach my $element ( @{$array} ) {
		push @results, $element if ! $exclude{$element};
	} # end foreach
	return @results;
} # end sub exclude

sub max {
	my $max;

	foreach ( ( ( @_ == 1 ) and ( ref $_[0] eq 'ARRAY' ) ) ? @{$_[0]} : @_ ) {
		$max = $_ if ( ! defined $max ) or  ($max < $_ );
	} # end foreach
	return $max;
} # end sub max

sub max_index {
	my $array = ( ( @_ == 1 ) and ( ref $_[0] eq 'ARRAY' ) ) ? $_[0] : \@_;
	my $max;
	my $max_index;

	for ( my $index = 0; $index < @$array; $index += 1 ) {
		if ( ( ! defined $max ) or ($max < $$array[$index] ) ) {
			$max = $$array[$index];
			$max_index = $index;
		} # endif
	} # end foreach
	return $max_index;
} # end sub max_index

sub equal {
	my ( $array1, $array2 ) = @_;
	return 0 if @{$array1} != @{$array2};
	for ( my $i = 0; $i < @{$array1}; $i += 1 ) {
		return 0 if $$array1[$i] != $$array2[$i];
	} # end for
	return 1;
} # end sub equal

# returns the index matching
sub index {
	my $value = shift;
	for ( my $i = 0; $i < @_; $i += 1 ) {
		return $i if $_[$i] eq $value;
	} # end for
	return -1;
} # end sub index

1;
__END__
