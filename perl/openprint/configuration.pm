use strict;
package openprint::configuration;

require openprint;
use vars qw( %config );

require sql;

*config = \%openprint::config;

sub init {
	
	%config = ();
	if ( $openprint::dbh ) {
		my $data = $openprint::dbh->selectall_arrayref( 'SELECT strconfigtitle, strconfigdata FROM tbl_configuration', {Slice=>{}} );
		foreach (@{$data}) {
			$config{$$_{name}} = $$_{value};
		} # end foreach
	} # end if
	
	# Anything specified in dir_config override configuration
	if ( @_ ) {
		@config{ keys %{$_[0]}} = values %{$_[0]};
	} # end if
} # end sub init

sub get_values {
	my ( $log, $dbh, @names ) = @_;

	$_ = "SELECT Name, Value FROM Configuration WHERE Name IN ('".join("','", @names ) ."')";
	my %results = sql::execute( $log, $dbh, $_ );
	return @results{@names};

} # end sub get_values 

sub get_entry {
	my ( $log, $dbh, $name ) = @_;

	return sql::execute( $log, $dbh, 'SELECT Name, Value FROM Configuration WHERE Name=?', $name );
} # end sub get_entry

sub save_entry {
	my ( $log, $dbh, $name, $value ) = @_;

	my %entry = get_entry( $log, $dbh, $name );
	if ( %entry ) {
		if ( $entry{$name} ne $value ) {
			update_entry( $log, $dbh, $name, $value );
		} # end if
	} else {
		insert_entry( $log, $dbh, $name, $value );
	} # end if
} # end sub save_entry

sub insert_entry {
	my ( $log, $dbh, $name, $value ) = @_;
	$name =~ s/^\s*(.*?)\s*$/$1/;
	$value =~ s/^\s*(.*?)\s*$/$1/;
	sql::insert( $log, $dbh, 'Configuration', 'Name', $name, 'Value', $value ); 
	$config{$name} = $value;
} # end sub insert_entry

sub update_entry {
	my ( $log, $dbh, $name, $value ) = @_;
	
	$name =~ s/^\s*(.*?)\s*$/$1/;
	$value =~ s/^\s*(.*?)\s*$/$1/;
	sql::update( $log, $dbh, 'Configuration', ['Name=?', $name], 'Value', $value );
	$config{$name} = $value;
} # end sub update_entry

sub save_config {
}

sub get_config {
	my ( $log, $dbh ) = @_;
   
	%config = sql::execute( $log, $dbh, 'SELECT Name, Value FROM Configuration' );
	return \%config;
} # end sub get_config

sub merge { 
	@config{keys %{$_[0]}} = values %{$_[0]};
} # end sub merge

sub merge_defaults { 
	foreach my $k ( keys %{$_[0]} ) {
		$config{$k} = $_[0]{$k} if ! $config{$k};
	} # end foreach
} # end sub merge_defaults

sub from_file {
	my $file = $_[0];
# Process the contents of the config file
	our %Config;
	my $rc = do($file);

# Check for errors
	if ($@) {
		$openprint::log->error( "ERROR: Failure compiling '$file' - $@" );
		return "ERROR: Failure compiling '$file' - $@";
	} elsif (! defined($rc)) {
		$openprint::log->error( "ERROR: Failure reading '$file' - $!" );
		return "ERROR: Failure reading '$file' - $!";
	} elsif (! $rc) {
		$openprint::log->error( "ERROR: Failure processing '$file'" );
		return "ERROR: Failure processing '$file'";
	}
	@config{keys %Config} = values %Config;
	return;
} # end sub from_file

sub from_db {
	if ( $openprint::dbh ) {
		my $data = $openprint::dbh->selectall_arrayref( 'SELECT name, value FROM Configuration', {Slice=>{}} );
		foreach (@{$data}) {
#$openprint::log->debug("Assigning $$_{name}=>$$_{value} to config.".($config{$$_{name}} ? "overwriting previous value $config{$$_{name}}" : ''));
			$config{$$_{name}} = $$_{value};
		} # end foreach
	} # end if
} # end sub from_db

sub dump {
	foreach ( sort { $a cmp $b } keys %config ) {
		print "$_ => $config{$_}\n";
	}
}

1;
__END__
