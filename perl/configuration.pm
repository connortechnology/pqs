package configuration;
use strict;
use warnings;

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
