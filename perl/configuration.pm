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

sub get_values {
    my ($log, $dbh, @names) = @_;

    my $placeholders = join(',', ('?') x scalar @names);

    my %results = @{ $dbh->selectcol_arrayref(qq{
        SELECT strConfigTitle, strConfigData 
        FROM tbl_Configuration 
        WHERE strConfigTitle IN ($placeholders)
    }, { Columns => [1,2] }, @names) };

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
