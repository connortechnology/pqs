package PQS::DB;
use strict;
# use warnings;

use DBI  ();
use Carp ();
use Apache2::RequestUtil ();

# Takes an Apache request object to get the database connection information
# from the Apache configuration and returns an opened database handle.
sub connect {
    my ($class, $r, $options) = @_;

    die "Need an Apache object to get configuration directives." 
        unless (ref $r) =~ /^Apache(::Request)?/;

    # Perl to Apache database var config mapping.
    my %db = (
        database => 'database',
        driver   => 'db_driver',
        host     => 'db_host',
        user     => 'db_user',
        port     => 'db_port',
        pass     => 'db_password',
    );
    
    # Get values from Apache config.
    $db{$_} = $r->dir_config( $db{$_} ) for keys %db;

    # Create the DSN string.
    my $dsn = dsn( $db{driver}, $db{database}, $db{host}, $db{port} );

    # Set the default handle attributes.
    my %attr = (
        AutoCommit => 0,
        RaiseError => 1,
        ShowErrorStatement => 1,
		#HandleError => \&_handle_error, # Can't be anon.
        pg_enable_utf8 => 1,
    );

    $attr{$_} = $options->{$_} for keys %$options; # Override defaults

    # Establish a connection to the database.
    my $dbh = DBI->connect($dsn, $db{user}, $db{pass}, \%attr);

    unless ($dbh) {
        my $err = "Can't connect to DB: $dsn. " . DBI->errstr;
        $r->log->crit($err);
        die $err;
    }

    return $dbh;
}

# Log error messages before dieing. NOTE: Do not make this an anonymous
# function in the connection; or each request will have a different coderef
# which will register as a different connection to Apache2::DBI.
sub _handle_error {
    my ($err) = @_;
    die $err;
}


# Create a DSN string from the driver, database and (optionally) host name
# provided. DSNs formats are driver dependent, currently only the Pg format is
# supported.
sub dsn {
    my ($driver, $database, $host, $port) = @_;
    
    # Create the DBI DSN.
    my $dsn  = sprintf "dbi:%s:dbname=%s", $driver, $database;
       $dsn .= sprintf ";host=%s",         $host if $host;
       $dsn .= sprintf ";port=%d",         $port if $port;

    # Return the connection information.
    return $dsn;
}


1;
