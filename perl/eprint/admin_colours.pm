package eprint::admin_colours; # Handles import and export of the ink table.
use strict;

use Text::CSV_XS;
use sql  ();
use misc ();

# Colour Definitions Import/Export
sub import_export {
    my ( $r, $log, $dbh, $variable ) = @_;

    if ($r->param('btnFunction') eq 'Import Colours') {
        import_colours($r, $log, $dbh);
    } 
    elsif ($r->param('btnFunction') eq 'Export Colours') {
        export_colours($r, $log, $dbh, $variable);
    }
}

sub import_colours {
    my ($r, $log, $dbh) = @_;

    unless ($r->param('fileColour')) {
        $log->error("No upload file specified.");
        return;
    }
    
    $dbh->do(q{DELETE FROM tbl_Ink_Colours});

    # get the upload.
    my @content = misc::get_upload($r, $log, 'fileColour');
    shift @content; # drop the title row

    # convert it
    my $csv = Text::CSV_XS->new();

    foreach my $line ( @content ) {
        my $status = $csv->parse($line);         # parse a CSV string into fields

        my ($pms_id, $service, $material, $desc) = $csv->fields();

        $pms_id   =~ s/^\s*(.*?)\s*$/$1/;
        $service  =~ s/^\s*(.*?)\s*$/$1/;
        $material =~ s/^\s*(.*?)\s*$/$1/;
        $desc     =~ s/^\s*(.*?)\s*$/$1/;

        sql::insert($log, $dbh, 'tbl_Ink_Colours',  
            strPMSID      => $pms_id,
            strServiceID  => $service,
            strMaterialID => $material,
            strColourName => $desc,
        );
    }
}

sub export_colours {
    my ($r, $log, $dbh, $variable) = @_;

    my @header = ('PMSId', 'Serivce ID', 'Material ID', 'Colour Name');

    my @data = sql::sql_statement( $log, $dbh, q{
        SELECT strPMSID, strServiceId, strMaterialID, strColourName 
        FROM tbl_Ink_Colours
    });

    misc::export_csv($r, $log, $variable, 'colours.csv', \@header, \@data);
}

1;
