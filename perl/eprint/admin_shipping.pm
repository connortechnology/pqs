package eprint::admin_shipping;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use Text::CSV_XS;

use sql ();
require misc;
require eprint::equipment;

# Service Definitions Import/Export
sub zone_import {
	my ( $r, $log, $dbh, $variable ) = @_;
	$log->debug("**** START ZONE IMPORT ****");

	my $ship_index = $r->param('ddmShipVia');

	if ( $r->param('btnFunction') eq 'Import Zones' ) {
		if ( $r->param('fileZones') ne '' ) {

			if ( $r->param('chkDeleteZones') eq 'Y' ) {
				$_ = "DELETE FROM tbl_Shipping_Zones WHERE lngShipViaIndex='$ship_index'";	
				sql::sql_statement( $log, $dbh, $_ );
			} # end if

			# get the upload.
			my @content = misc::get_upload( $r, $log, 'fileZones' );
			#convert it
			my $csv = Text::CSV_XS->new();
			shift @content; # drop the title row
			foreach my $line ( @content ) {
				my $status = $csv->parse($line);		 # parse a CSV string into fields

				my ( $number, $id, $name, $desc, $country ) = misc::trim( $csv->fields() );

				#my ($index) = sql::sql_statement( $log, $dbh, "SELECT strID FROM tbl_Shipping_Zones WHERE strID = '$id' " );
				my $index = ''; #lets try no updates, inserts only.
				
				my @params = (
					'lngShipViaIndex',	$ship_index,
					'lngZoneNumber',	$number,
					'strID',			$id,
					'strName',			$name,
					'strDescription',	$desc,
					'strCountry',		$country,
				);
				if ( $id ne '' ) {
					if ( $index eq '' ) {
						sql::insert( $log, $dbh, 'tbl_Shipping_Zones', @params );
					} else {
						sql::update( $log, $dbh, 'tbl_Shipping_Zones', "strId='$index'", @params );
					} # end if
				} # end if
			} # end while
		} else {
			$log->warn( "No file given to upload." );
		} # end if 
	 } elsif ( $r->param('btnFunction') eq 'Import Lookup' ) {
		if ( $r->param('fileZoneLookup') ne '' ) {

			if ( $r->param('chkDeleteZoneLookup') eq 'Y' ) {
				$_ = "DELETE FROM tbl_Zone_Lookup WHERE lngShipViaIndex='$ship_index'";	
				sql::sql_statement( $log, $dbh, $_ );
			} # end if

			# get the upload.
			my @content = misc::get_upload( $r, $log, 'fileZoneLookup' );
			#convert it
			my $csv = Text::CSV_XS->new();
			shift @content; # drop the title row
			foreach my $line ( @content ) {
				my $status = $csv->parse($line);		 # parse a CSV string into fields

				my ( $id, $start, $end ) = misc::trim( $csv->fields() );


				my @params = (
					'lngShipViaIndex', 	$ship_index,
					'strId',		$id,
					'strStartRange',	$start,
					'strEndRange',		$end,
				);

				sql::insert( $log, $dbh, 'tbl_Zone_Lookup', @params );

			} # end while
		} else {
			$log->warn( "No file given to upload." );
		} # end if
	 } elsif ( $r->param('btnFunction') eq 'Import Prices' ) {
		if ( $r->param('chkDeletePrices') eq 'Y' ) {
			$_ = "DELETE FROM tbl_Shipping_Prices WHERE lngShipViaIndex='$ship_index' AND lngListIndex='" . $r->param('ddmPriceList') . "'";	
			sql::sql_statement( $log, $dbh, $_ );
		} # end if
		if ( $r->param('fileImportPrices') ne '' ) {
						# get the upload.
			my @content = misc::get_upload( $r, $log, 'fileImportPrices' );
			#convert it
			my $csv = Text::CSV_XS->new();
			shift @content; # drop the title row
			foreach my $line ( @content ) {
				my $status = $csv->parse($line);		 # parse a CSV string into fields

				my ( $from, $to, $min, $max, $units, $cost, $markup ) = misc::trim( $csv->fields() );

				$min = 'NULL' if $min eq '';
				$max = 'NULL' if $max eq '';

				$cost =~ tr /0-9.//cd;
				$markup =~ tr /0-9.//cd;


				my @params = (
					'lngShipViaIndex', 	$ship_index,
					'lngListIndex', $r->param('ddmPriceList'),
					'strFromZone',		$from,
					'strToZone',		$to,
					'lngMin',			$min,
					'lngMax',			$max,
					'strUnits',			$units,
					'dblCost',			$cost,
					'dblMarkup',		$markup,
				);

				sql::insert( $log, $dbh, 'tbl_Shipping_Prices', @params );

			} # end while
		} else {
			$log->warn( "No file given to upload." );
		} # end if
	} elsif ( $r->param('btnFunction') eq 'Save' ) {

			my @params = (
			'strName',			$r->param('strName'),
			'strID',			$r->param('strID'),
			'strDescription',	$r->param('strDescription'),
			);
			if ( $ship_index eq '' ) {
				sql::insert( $log, $dbh, 'tbl_Ship_Via', @params );
				$ship_index = $dbh->selectrow_array(q{
					SELECT max(lngindex) FROM tbl_ship_via
				});
			} else {
				sql::update( $log, $dbh, 'tbl_Ship_Via', "lngIndex='$ship_index'", @params );
			} # end if

	} elsif ( $r->param('btnFunction') eq 'Delete' ) {

			sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Shipping_Prices WHERE lngShipViaIndex='$ship_index'" );
			sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Shipping_Zones WHERE lngShipViaIndex='$ship_index'" );
			sql::sql_statement( $log, $dbh, "DELETE FROM tbl_zone_lookup WHERE lngShipViaIndex='$ship_index'" );
			sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Ship_Via WHERE lngIndex='$ship_index'" );

	} elsif ( $r->param('btnFunction') eq 'Export Zones' ) {
        # We can't export a zone something we don't have.
        return unless $ship_index;
        # Gather and export the data.
		my @header = ( 'Zone #', 'Zone ID','Name', 'Description', 'Country' );
		$_ = "SELECT lngZoneNumber, strID, strName, strDescription, strCountry FROM tbl_Shipping_Zones ".
			 " WHERE lngShipViaIndex='$ship_index'";
		my @data = sql::sql_statement( $log, $dbh, $_ );
		misc::export_csv( $r, $log, $variable, 'zones.csv', \@header, \@data );
	} elsif ( $r->param('btnFunction') eq 'Export Lookup' ) {
        # We can't export a zone something we don't have.
        return unless $ship_index;
        # Gather and export the data.
		my @header = ( 'Zone ID', 'Start Range', 'End Range' );
		$_ = "SELECT strID, strStartRange, strEndRange  FROM tbl_Zone_Lookup ".
			 " WHERE lngShipViaIndex='$ship_index'";
		my @data = sql::sql_statement( $log, $dbh, $_ );
		misc::export_csv( $r, $log, $variable, 'lookup.csv', \@header, \@data );
	} elsif ( $r->param('btnFunction') eq 'Export Prices' ) {
        # We can't export a zone something we don't have.
        return unless $ship_index;
        # Gather and export the data.
		my @header = ( 'From Zone', 'Destination Zone', 'Minimum Weight', 'Maximum Weight', 'Units', 'Cost', 'Markup' );
		$_ = "SELECT strFromZone, strToZone, lngMin, lngMax, strUnits, dblCost, dblMarkup FROM tbl_Shipping_Prices ".
			 " WHERE lngListIndex = '" .$r->param('ddmPriceList') . "' AND lngShipViaIndex='$ship_index'";
		my @data = sql::sql_statement( $log, $dbh, $_ );
		misc::export_csv( $r, $log, $variable, 'prices.csv', \@header, \@data );
	} # end if
	$_ = "SELECT lngIndex, strName FROM tbl_Ship_Via ORDER by strName";
	my $currency_index = '';
	$$variable{'ddmShipVia'} = ssi::fill_drop_down( $log, $dbh, $_, $ship_index ); 

    @$variable{'strName', 'strID', 'strDescription'} = $dbh->selectrow_array(q{
        SELECT strName, strId, strDescription 
        FROM tbl_Ship_Via
        WHERE lngIndex = ?
    }, undef, $ship_index);

	$_ = "SELECT id, currency || '-' || name FROM pricelist ORDER BY name";
	$$variable{'ddmPriceList'} = ssi::fill_drop_down( $log, $dbh, $_, join('',$r->param('ddmPriceList')) );
}


1;
