package sql;

# DESCRIPTION
#
#   A few wrapper/utility function around DBI. Highly DEPRECATED.
#

use strict;
use warnings;                   # Turn off for production version.
no  warnings qw(uninitialized); # Interpolating undef into strings is okay.
use Time::HiRes qw{ gettimeofday tv_interval };
require openprint;

use base qw(Exporter);
use constant DEBUG=>1;
use constant TIMING=>1;

our @EXPORT_OK = qw(
execute
    sql_statement
    insert
    update
    escape
);

our %EXPORT_TAGS = ( all    => \@EXPORT_OK,
                     common => [ qw(sql_statement insert update) ] );


sub execute {
  my ( $l, $d, $sql, @values ) = @_;
  my @return_array = ();
  my $print_sql = $sql;
  my $starttime;

  $l = $openprint::log if ! defined $l;
  $d = $openprint::dbh if ! $d;

  if ( $l and DEBUG ) {
    $print_sql = $sql;
    $print_sql =~ s/\?/\%s/g;
    $print_sql = sprintf($print_sql, @values);
     $starttime = [gettimeofday] if TIMING;
   } # end if
   my $sth;
   if ( ! $d ) {
     $l->error( "No dbh $print_sql" ) if $l;
     return;
   } # end if
   if ( ! ( $sth = $d->prepare_cached($sql) ) ) {
     $l->error( "Error Preparing SQL: ($print_sql): " . $d->errstr ) if $l;
     return;
   } # end if
   #$l->warn($sql);
   if ( ! $sth->execute(@values) ) {
     $l->error("SQL execution failed: ($print_sql):" . $d->errstr) if $l;
     return;
   } # end if
   if ( my $num_of_fields = $sth->{'NUM_OF_FIELDS'} ) {
     while ( my $ref = $sth->fetchrow_arrayref ) {
       push @return_array, @$ref;

       #for ( my $i = 0; $i < $num_of_fields; $i += 1 ) {
       #push @return_array, $$ref[$i];
       #} # end for
     } # end while
   } # end if
   $sth->finish();
   if ( $l and DEBUG ) {
     if ( TIMING ) {
       $l->debug("SQL (".sprintf('%.4f', tv_interval($starttime)*1000)." usecs). ($print_sql) Results:".join(',',@return_array));
     } elsif ( @return_array ) {
       $l->debug("SQL ($print_sql) Results:".join(',',@return_array));
     } else {
       $l->debug("SQL ($print_sql) No Results:");
     } # end if
   } # end if

   return @return_array if wantarray;
   return \@return_array;
 } # end sub execute

# DEPRECATED. Runs the given SQL statement and returns the values AS A FLAT
# LIST! There is NO way to determine the number of fields per record or how
# many records you have.
sub sql_statement {
    my ($log, $dbh, $sql) = @_;


	die("Bad dbh") unless $dbh;

  print STDERR "$sql\n";
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
    $log = $openprint::log if ! $log;
    my $dbh   = shift;
    $dbh = $openprint::dbh if ! $dbh;
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

    print STDERR "$sql ".join(',', keys %data).'='.join(',',values %data)."\n" if DEBUG;
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
    my @condition_values;
    if (defined $condition and $condition ne '') {
      if (ref $condition eq 'ARRAY') {
        $sql .= ' WHERE '. shift @{$condition};
        @condition_values = @{$condition};
      } else {
        $sql .= " WHERE $condition "
      }
    }

    # Some code passes NULL as a string instead of as undef. Bad code, no
    # biscuit.
    #Change empty strings to undefined, DBI will convert undefiend to NULL
    #prevents sql errors for inserting empty strings into numeric fields
    for my $k (keys %data) {
      $data{$k} = undef if $data{$k} eq 'NULL' or $data{$k} eq '';
    }

    if ( $log ) {
      my $starttime = [gettimeofday] if TIMING;
      my $sth = $dbh->prepare($sql);
      $sth->execute(@condition_values, values %data );
      my $print_sql = $sql;
      $print_sql =~ s/\?/\%s/g;
      $print_sql = sprintf($print_sql, values %data );
      $log->debug( sprintf('SQL (%.4f usecs) (%s)', tv_interval( $starttime, [gettimeofday])*1000, $print_sql ) );
    } # end if

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
sub start_transaction {
  #my ( $caller, undef, $line ) = caller;
#$openprint::log->debug("Called start_transaction from $caller : $line");
  my $d = shift;
  $d = $openprint::dbh if ! $d;
  my $ac = $d->{AutoCommit};
  $d->{AutoCommit} = 0;
  return $ac;
} # end sub start_transaction

sub end_transaction {
  #my ( $caller, undef, $line ) = caller;
#$openprint::log->debug("Called end_transaction from $caller : $line");
  my ( $d, $ac ) = @_;
if ( ! defined $ac ) {
  $openprint::log->error("Undefined ac");
}
  $d = $openprint::dbh if ! $d;
  if ( $ac ) {
    #$log->debug("Committing");
    $d->commit();
  } # end if
  $d->{AutoCommit} = $ac;
} # end sub end_transaction


1;
