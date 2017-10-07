package sql;

# DESCRIPTION
#
#   A few wrapper/utility function around DBI. Highly DEPRECATED.
#

use strict;
use warnings;                   # Turn off for production version.
no  warnings qw(uninitialized); # Interpolating undef into strings is okay.

use base qw(Exporter);

our @EXPORT_OK = qw(
    sql_statement
    insert
    update
    escape
);

our %EXPORT_TAGS = ( all    => \@EXPORT_OK,
                     common => [ qw(sql_statement insert update) ] );


# DEPRECATED. Runs the given SQL statement and returns the values AS A FLAT
# LIST! There is NO way to determine the number of fields per record or how
# many records you have.
sub sql_statement {
    my ($log, $dbh, $sql) = @_;

    my $sth = $dbh->prepare($sql);
       $sth->execute;

    # If the statemet wasn't a query (ie. DELETE) return no results.
    return () unless $sth->{NUM_OF_FIELDS};

    # Throw all the records fields into a single list. I can only imagine this
    # method is a remenant of Perl 4 before references. It's now cleaned up
    # but the result must stay the same for legacy stuff.
    my @results;
    push @results, @$_ while $_ = $sth->fetch;

    # Otherwise return the result set.
    return @results;
}


# Given a log, dbh, table and field/value pairs creates a properly quoted and
# placeholdered (a new verb?) INSERT statement and executes it against the
# database.
sub insert {
    my $log   = shift;
    my $dbh   = shift;
    my $table = shift; # The table name to operate on (may contain schema)
    my %data  = @_;    # Field and value pairs

    # Identifiers (schema, table, fields, etc.) are lowercased before they're
    # quoted as some section of the code use mixed case, relying on Pg's case
    # folding of unquoted identifiers. These section should be revised
    # whenever possible.
    my $sql = sprintf "INSERT INTO %s (%s) VALUES (%s)",
        $dbh->quote_identifier( lc( $table ) ),
        (join ', ', map {$dbh->quote_identifier(lc($_))} keys %data),
        (join ', ', ('?') x scalar keys %data)
    ;

    # Some code passes NULL as a string instead of as undef. Bad code, no
    # biscuit.
    for my $k (keys %data) { $data{$k} = undef if $data{$k} eq 'NULL'; }

    my $sth = $dbh->prepare($sql);
       $sth->execute( values %data );

    # We should think about returning the number of records effected.
    return 1;
}

# Given a log, dbh, table and field/value pairs creates a properly quoted and
# placeholdered (a new verb?) UPDATE statement and executes it against the
# database.
sub update {
    my $log       = shift;
    my $dbh       = shift;
    my $table     = shift; # The table name to operate on (may contain schema)
    my $condition = shift; # A filter (WHERE) condition
    my %data      = @_;    # Field and value pairs

    # Identifiers (schema, table, fields, etc.) are lowercased before they're
    # quoted as some section of the code use mixed case, relying on Pg's case
    # folding of unquoted identifiers. These section should be revised
    # whenever possible.
    my $sql = sprintf "UPDATE %s SET %s",
        $dbh->quote_identifier( lc( $table ) ),
        join ', ', map {$dbh->quote_identifier(lc($_)) . ' = ?'} keys %data
    ;
    # If there's a condition sent include it in the statement.
    $sql .= " WHERE $condition " if defined $condition and $condition ne '';

    # Some code passes NULL as a string instead of as undef. Bad code, no
    # biscuit.
    for my $k (keys %data) { $data{$k} = undef if $data{$k} eq 'NULL'; }

    my $sth = $dbh->prepare($sql);
       $sth->execute( values %data );

    # We should think about returning the number of records affected.
    return 1;
}

# DEPRECATED. Escapes characters. A much better version is
# available as part of DBI. Or better yet use placeholders.
sub escape {
    $_ = shift;
    s/\\/\\\\/g;
    s/(['"])/\\$1/g;
    return $_;
}

1;
