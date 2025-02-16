package configuration;
use strict;
use warnings;

require openprint;
use vars qw( %config );
*config = \%openprint::config;

sub init {

  %config = ();
  if ( $openprint::dbh ) {
    my $data = $openprint::dbh->selectall_arrayref( 'SELECT strconfigTitle AS name, strconfigdata AS value FROM tbl_Configuration', {Slice=>{}} );
    foreach (@{$data}) {
      $config{$$_{name}} = $$_{value};
    } # end foreach
  } # end if

  # Anything specified in dir_config override configuration
  if ( @_ ) {
    @config{ keys %{$_[0]}} = values %{$_[0]};
  } # end if
} # end sub init


sub get_value {
	my ($log, $dbh, $name) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT strConfigData 
        FROM tbl_Configuration 
        WHERE strConfigTitle = ?
        LIMIT 1
    });

    return scalar $dbh->selectrow_array($sth, undef, $name);
}

sub get_category {
    my ($log, $dbh, $id) = @_;


    my $results = $dbh->selectall_arrayref(qq{
        SELECT  *, strconfigdata as value
        FROM tbl_Configuration 
        WHERE category = ? ORDER by sortval } , { Slice => {} }, $id );

	use Data::Dumper;
	print STDERR "RESULTS", Dumper($results);

    return $results; 
}

sub get_values {
    my ($log, $dbh, @names) = @_;

    my $placeholders = join(',', ('?') x scalar @names);

    my %results = @{ $dbh->selectcol_arrayref(qq{
        SELECT strConfigTitle, strConfigData, label 
        FROM tbl_Configuration 
        WHERE strConfigTitle IN ($placeholders)
    }, { Columns => [1,2,3] }, @names) };

    return @results{@names};
}

sub save_entry {
	my ($log, $dbh, $name, $value) = @_;

    if (entry_exists($log, $dbh, $name)) {
        $dbh->do(q{
            UPDATE tbl_configuration 
                SET strconfigtitle = ?,
                    strconfigdata  = ?
            WHERE strconfigtitle = ?
        }, undef, $name, $value, $name);
    }
    else {
        $dbh->do(q{
            INSERT INTO tbl_configuration (strconfigtitle, strconfigdata) 
            VALUES (?,?)
        }, undef, $name, $value);
    }
    return 1;
}

sub entry_exists {
	my ( $log, $dbh, $name ) = @_;

    my $sth = $dbh->prepare_cached(q{
        SELECT true
        FROM tbl_Configuration 
        WHERE strConfigTitle = ?
        LIMIT 1
    });

    return $dbh->selectrow_array($sth, undef, $name);
}

1;
