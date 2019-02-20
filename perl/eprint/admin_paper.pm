package eprint::admin_paper;
use strict;
use utf8;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use Text::CSV_XS;
use sql qw(:common);
use Data::Dumper;

require misc;

# For CSV
use constant N => 0; # Numeric (Should be 2, but Text::CSV is having problems)
use constant I => 1; # Int
use constant V => 0; # Varchar


my %id_by_index_cache;
my %index_by_id_cache;

sub get_id_by_index {
    my ($log, $dbh, $index ) = @_;

    if ( ! defined $id_by_index_cache{$index} ) {
        ( $_ ) = sql_statement( $log, $dbh, "SELECT strID FROM tbl_Paper WHERE lngIndex = '$index'" );
        $id_by_index_cache{$index} = $_;
        $index_by_id_cache{$_} = $index;
    }
    return $id_by_index_cache{$index};
}

sub get_index_by_id {
    my ( $log, $dbh, $id ) = @_;

    if ( ! defined $index_by_id_cache{$id} ) {
        ( $_ ) = sql_statement( $log, $dbh, "SELECT lngIndex FROM tbl_Paper WHERE strID = '$id'" );
        ( $_ ) = sql_statement( $log, $dbh, "SELECT lngIndex FROM tbl_Paper_Roll WHERE strID = '$id'" ) if not $_;
        $index_by_id_cache{$id} = $_;
        $id_by_index_cache{$_} = $id;
    }
    return $index_by_id_cache{$id};
}

sub save {
    my ( $r, $log, $dbh, $index, $make_copy ) = @_;

    my @fields = qw(
        strID                strName              strCategory
        strDetails           strCalliper          strColour
        strFinish            strMWeight           strWeight
        dblWidth             dblHeight            dbl1TonPrice
        dbl5TonPrice         dbl20TonPrice        dblEndBracketPrice
        dblBrokenCartonPrice dblOtherPrice		  lngpaperlistindex 
    );

    my %substrate; 
    for my $attr (@fields) {
        my $value = $r->param($attr);
        
        next unless $value; # Skip the field if it's NULL

        $substrate{$attr} = $value;
    }
	$substrate{strID} .= "-copy" if $make_copy;

    # We have two oddball names, instead of making the entire list above a
    # hashmap we'll just handle them here.
    $substrate{ysnPerfecting} = $r->param('rdbPerfecting');      # ysn <-> rdb
    $substrate{lngPackageQty} = $r->param('dblPackageQuantity'); # lng <-> dbl
    
    # The interface currently doesn't allow editing of the template but a
    # non-NULL one is needed. TODO See bug 2641.
    $substrate{strtemplate} = '';

    return unless %substrate;


	print STDERR "SAVE PAPER: ", Dumper(\%substrate);
    if (!$index) {
        insert( $log, $dbh, 'tbl_Paper', %substrate );
        $index = $dbh->last_insert_id(undef, undef, 'tbl_paper', 'lngindex');
    } 
    else {
        update($log, $dbh, 'tbl_Paper', "lngIndex = $index", %substrate);
    }

	save_price($r);

    return $index;
}

sub save_price {
		my $r = session::r;
		my $log = session::log;
		my $dbh = session::dbh;

		my %price_sets;
		foreach my $key ( $r->param() ) {
			if ( $key =~ /chk-(.*)-(.*)-(.*)/ ) {
				my ( $listIndex, $paperIndex, $priceIndex ) = ($1, $2, $3);
				my $setId = $listIndex.'-'.$paperIndex;
				$log->debug("PRICE SET: $listIndex - $paperIndex ");
				$price_sets{$setId} = new eprint::admin_paper::priceset( $log, $dbh, $listIndex, $paperIndex ) if  ! defined $price_sets{$setId};
				if ( $r->param("rdbIncluded-$listIndex-$paperIndex") eq 'Y' ) {
					my $price = new eprint::admin_paper::price( $log, $dbh, $price_sets{$setId} );
					$price->set(
							'', # No Equipment
							$r->param("txtMin-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtMax-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtUnits-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtCost-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtMarkup-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtPrice-$listIndex-$paperIndex-$priceIndex"),
							$r->param("rdbDiscount-$listIndex-$paperIndex-$priceIndex")
							);
					$price_sets{$setId}->addPrice( $price );
				} # end if
			} # end if
        } # end foreach
		foreach my $set ( keys %price_sets ) {
			$price_sets{$set}->save();
		} # end if

}

sub paper_prices {
	my ( $r, $log, $dbh, $variable ) = @_;
	my ( $temp );

	my $index = $r->param('ddmPaper');
	my $type = $r->param('rdbType');

	$r->param('ddmSheetSize') =~ /(\d*\.*\d*)x(\d*\.*\d*)/;
	my $width = $1;
	my $height = $2;

	$width = $r->param('ddmSheetSize') unless $width;
	$variable->{__FillInForm}{rdbType} = $r->param('rdbType');

	if ( $r->param('btnFunction') eq 'Save' ) {
		my %price_sets;
		foreach my $key ( $r->param() ) {
			if ( $key =~ /chk-(.*)-(.*)-(.*)/ ) {
				my ( $listIndex, $paperIndex, $priceIndex ) = ($1, $2, $3);
				my $setId = $listIndex.'-'.$paperIndex;
				$log->debug("PRICE SET: $listIndex - $paperIndex ");
				$price_sets{$setId} = new eprint::admin_paper::priceset( $log, $dbh, $listIndex, $paperIndex ) if  ! defined $price_sets{$setId};
				if ( $r->param("rdbIncluded-$listIndex-$paperIndex") eq 'Y' ) {
					my $price = new eprint::admin_paper::price( $log, $dbh, $price_sets{$setId} );
					$price->set(
							'', # No Equipment
							$r->param("txtMin-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtMax-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtUnits-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtCost-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtMarkup-$listIndex-$paperIndex-$priceIndex"),
							$r->param("txtPrice-$listIndex-$paperIndex-$priceIndex"),
							$r->param("rdbDiscount-$listIndex-$paperIndex-$priceIndex")
							);
					$price_sets{$setId}->addPrice( $price );
				} # end if
			} # end if
        } # end foreach
		foreach my $set ( keys %price_sets ) {
			$price_sets{$set}->save();
		} # end if
    }
    elsif ($r->param('btnFunction') eq 'Delete') {
        $log->error("ID: $index");
        $dbh->do(q{
            DELETE FROM tbl_paper_prices WHERE lngpaperindex = ?
        }, {}, $index);
    }

	if (($r->param('btnFunction') eq '>>') || ($r->param('btnFunction') eq '<<')){
		$_ = "SELECT lngIndex FROM tbl_Paper WHERE 1>0\n";
		$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
		$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
		$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
		$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
		$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
		$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
		$_ .= "AND dblWidth = '$width'\n" if $width ne '';
		$_ .= "AND dblHeight = '$height'\n" if $height ne '';
		$_ .= "ORDER BY strID";
		my @papers_array = sql::sql_statement( $log, $dbh, $_ );
		for (my $i=0; $i< @papers_array; $i++) {
			if ($index == $papers_array[$i]){
				if ($r->param('btnFunction') eq '>>') {
					$i = -1
					if ($i == (scalar @papers_array) - 1);
					$index = $papers_array[$i+1];
				}else {
					$i = scalar @papers_array
					if ($i == 0);
					$index = $papers_array[$i-1];
				}
				last;
			}
		}
	}


	my $q;
	if ( $type ne 'roll' ) {
			# populate drop downs
			$q = "SELECT lngIndex, strID FROM tbl_Paper WHERE 1>0\n";
			$q .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
			$q .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
			$q .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
			$q .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
			$q .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
			$q .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
			$q .= "AND dblWidth = '$width'\n" if $width ne '';
			$q .= "AND dblHeight = '$height'\n" if $height ne '';
			$q .= "ORDER BY strID";
	} else
	{
			# populate drop downs
			$q = "SELECT lngIndex, strID FROM tbl_Paper_Roll WHERE 1>0\n";
			$q .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
			$q .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
			$q .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
			$q .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
			$q .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
			$q .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
			$q .= "AND dblWidth = '$width'\n" if $width ne '';
			$q .= "ORDER BY strID";
	}

	$$variable{'ddmPaper'} = ssi::fill_drop_down( $log, $dbh, $q, $index );

	my %selected_papers = sql::sql_statement( $log, $dbh, $q );

	my @options = keys %selected_papers;

	my @papers = $r->param('ddmPaper') ? $r->param('ddmPaper') : keys %selected_papers;
	@papers = $index if ($r->param('btnFunction') eq '>>') || ($r->param('btnFunction') eq '<<');

	# only do the following code if there is a paper selected
	if ( $r->param('btnFunction') eq 'Display' or $r->param('btnFunction') eq 'Save' or $r->param('ddmPaper') ) {	
		$_ = "SELECT currency || '-' || name, id FROM pricelist";
		my %price_lists = sql::sql_statement( $log, $dbh, $_ );
		foreach my $paperIndex ( @papers ) {
			foreach my $listId ( keys %price_lists ) {
				my $listIndex = $price_lists{$listId};
				my $paperId = $selected_papers{$paperIndex};
				my @prices = sql::sql_statement($log, $dbh, qq{
                    SELECT lngMin::INT4, lngMax::INT4, strUnits, trunc(dblCost,2), dblMarkup, trunc(dblPrice,2), ysnDiscountable 
                    FROM tbl_Paper_Prices 
                    WHERE lngListIndex = $listIndex AND lngPaperIndex = $paperIndex
                    ORDER BY lngMax
                });

				@prices = ('','','','','','','') if ( @prices == 0 );
				$log->debug("Pushing Prices; @prices ");

				while ( @prices ) {
					push @{$$variable{'Prices'}}, $listId, $listIndex, $paperId, $paperIndex, splice(@prices,0,7);
					$log->debug("Dumping Prices: @{$$variable{'Prices'}}");
				} # end while
			} #end for list
		} # end for paper

#			$_ = "SELECT (Select strName FROM tbl_Price_Lists where lngIndex=tbl_Paper_Prices.lngListIndex), lngListIndex, strID, lngPaperIndex, lngMin::INT4, lngMax::INT4, strUnits, trunc(tbl_Paper_Prices.dblCost,2), tbl_Paper_Prices.dblMarkup, trunc(tbl_Paper_Prices.dblPrice,2) ".
#			" FROM tbl_Paper, tbl_Paper_Prices ".
#			" WHERE tbl_Paper_Prices.lngPaperIndex = tbl_Paper.lngIndex ";
#		    " AND lngIndex = " . $r->param('ddmPaper'); 
#			$_ .= " ORDER BY tbl_Paper.strID, tbl_Paper_Prices.lngListIndex, tbl_Paper_Prices.lngMax  ";
#		@{$$variable{'Prices'}} = sql::sql_statement( $log, $dbh, $_ );

	} # end if

	my $opts = "(". join(',',@options) . ")";

	if ( scalar @options ) {

			$_ = qq{
					SELECT DISTINCT strName, strName FROM tbl_Paper WHERE lngindex IN $opts
					UNION
					SELECT DISTINCT strName, strName FROM tbl_Paper_Roll WHERE lngindex IN $opts
					ORDER BY 1
			};
					
			$$variable{'ddmPaperName'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmPaperName') );

			$_ = qq{
					SELECT DISTINCT strCategory, strCategory FROM tbl_Paper WHERE lngindex IN $opts
					UNION
					SELECT DISTINCT strCategory, strCategory FROM tbl_Paper_Roll WHERE lngindex IN $opts
					ORDER BY 1
			};

			$$variable{'ddmCategory'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCategory') );

			$_ = qq{
					SELECT DISTINCT strFinish, strFinish FROM tbl_Paper WHERE lngindex IN $opts
					UNION
					SELECT DISTINCT strFinish, strFinish FROM tbl_Paper_Roll WHERE lngindex IN $opts
					ORDER BY 1
			};

			$$variable{'ddmFinish'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmFinish') );

			$_ = qq{
					SELECT DISTINCT strColour, strColour FROM tbl_Paper WHERE lngindex IN $opts
					UNION
					SELECT DISTINCT strColour, strColour FROM tbl_Paper_Roll WHERE lngindex IN $opts
					ORDER BY 1
			};

			$$variable{'ddmColour'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmColour') );

			$_ = qq{
					SELECT DISTINCT text(dblWidth) || 'x' || text(dblHeight), 
					text(dblWidth) || 'x' || text(dblHeight) FROM tbl_Paper WHERE lngindex IN $opts
					UNION
					SELECT text(dblWidth), text(dblWidth) || ' Inch Roll' FROM tbl_Paper_Roll where lngindex IN $opts
			};

			$$variable{'ddmSheetSize'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmSheetSize') );

			$_ = qq{
					SELECT DISTINCT strWeight, strWeight FROM tbl_Paper WHERE lngindex IN $opts
					UNION
					SELECT DISTINCT strWeight, strWeight FROM tbl_Paper_Roll WHERE lngindex IN $opts
					ORDER BY 1
			};
	}

	$$variable{'ddmWeight'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmWeight') );

	$_ = "SELECT lngIndex, strName FROM tbl_PaperLists ORDER BY strName";
	$$variable{'ddmPaperList'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmPaperList') );

	if ( $index ) {
	$_ = "SELECT strName, strID, strCategory\n".
						"FROM tbl_Paper WHERE lngIndex = '$index'";
		@$variable{'strPaperName','strPaperID','strCategoryID'} = sql::sql_statement( $log, $dbh, $_ );
	} # end if

    $variable->{Prices} = [] unless defined $variable->{Prices};

	return OK;
} # end sub


sub paper_edit {
	my ( $r, $log, $dbh, $variable ) = @_;
	my ( $temp );
	my $action = $r->param('btnFunction');
print STDERR "Start Paer Edit - $action \n";
	my $index = $r->param('ddmPaper');
	$r->param('ddmSheetSize') =~ /(\d*\.*\d*)x(\d*\.*\d*)/;
	my $width = $1;
	my $height = $2;

	if ( $r->param('btnFunction') eq '>>' ) {
		$temp = "SELECT MIN(lngIndex) FROM tbl_Paper WHERE strID > ( SELECT strID FROM tbl_Paper WHERE lngIndex='$index' )\n";
		$temp .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
		$temp .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
		$temp .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
		$temp .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
		$temp .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
		$temp .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
		$temp .= "AND dblWidth = '$width'\n" if $width ne '';
		$temp .= "AND dblHeight = '$height'\n" if $height ne '';
		( $index ) = sql::sql_statement( $log, $dbh, $temp );
	} elsif ( $r->param('btnFunction') eq 'Go') {
		$index = scalar $dbh->selectrow_array(q{
			SELECT lngindex 
			FROM tbl_paper
			WHERE strID = ?
		},undef, $r->param('txtGoPaperID'));
	} elsif ( $r->param('btnFunction') eq '<<' ) {
		$temp = "SELECT MAX(lngIndex) FROM tbl_Paper WHERE strID < ( SELECT strID FROM tbl_Paper WHERE lngIndex='$index' )\n";
		$temp .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
		$temp .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
		$temp .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
		$temp .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
		$temp .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
		$temp .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
		$temp .= "AND dblWidth = '$width'\n" if $width ne '';
		$temp .= "AND dblHeight = '$height'\n" if $height ne '';
		( $index ) = sql::sql_statement( $log, $dbh, $temp );
	} elsif ( $r->param('btnFunction') eq 'Delete' ) {
		if ( $index ) {
			$temp = "SELECT MIN(lngIndex) FROM tbl_Paper WHERE strID > ( SELECT strID FROM tbl_Paper WHERE lngIndex='$index' )\n";
			$temp .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
			$temp .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
			$temp .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
			$temp .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
			$temp .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
			$temp .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
			$temp .= "AND dblWidth = '$width'\n" if $width ne '';
			$temp .= "AND dblHeight = '$height'\n" if $height ne '';
			my ( $newindex ) = sql::sql_statement( $log, $dbh, $temp );

            $dbh->do(q{DELETE FROM tbl_paper_prices          WHERE lngPaperIndex = ?}, undef, $index);
            $dbh->do(q{DELETE FROM tbl_paper_recommendations WHERE lngPaperIndex = ?}, undef, $index);
            $dbh->do(q{DELETE FROM tbl_paper                 WHERE lngindex = ?}, undef, $index);

			$index = $newindex;
		}
	} elsif ( $r->param('btnFunction') eq 'Save' ) {
		$index = save( $r, $log, $dbh, $index );
	} elsif ( $r->param('btnFunction') eq 'Copy' ) {
		print STDERR "HAVE INDEX before copy: $index \n";

		my $old_index = $index;
		$index = save( $r, $log, $dbh, undef, 1 );
		$dbh->do(qq{INSERT into tbl_paper_prices  ( 
					select lnglistindex, $index, dtmstart, dtmend, lngmin, lngmax, strunits, dblcost, dblmarkup, dblprice, ysndiscountable 
					FROM tbl_paper_prices WHERE lngpaperindex = ? )
		}, undef, $old_index);
		print STDERR "HAVE INDEX after copy: $index \n";
	} # end if

	# only do the following code if there is a paper selected
	if ( $index ne '' ) {
		$_ = "SELECT strID, strName, strCategory, strDetails, strFinish, strColour, strMWeight, strWeight, strCalliper, dblWidth, dblHeight,\n".
			"dbl1TonPrice, dbl5TonPrice, dbl20TonPrice, dblOtherPrice, dblEndBracketPrice, dblBrokenCartonPrice,\n".
			"ysnTaxExempt1, ysnTaxExempt2, ysnPerfecting, lngPackageQty, lngpaperlistindex\n".
			"FROM tbl_Paper WHERE lngIndex = '$index'";
		@$variable{
			'strID', 'strName', 'strCategory','strDetails','strFinish', 'strColour', 'strMWeight', 'strWeight', 'strCalliper','dblWidth','dblHeight',
			'dbl1TonPrice','dbl5TonPrice','dbl20TonPrice','dblOtherPrice','dblEndBracketPrice','dblBrokenCartonPrice',
			'TaxExempt1','TaxExempt2','Perfecting', 'dblPackageQuantity', 'lngpaperlistindex'
		} = sql::sql_statement( $log, $dbh, $_ );

		$$variable{'rdbTaxExempt1'.$$variable{'TaxExempt1'}} = 'CHECKED';
		$$variable{'rdbTaxExempt2'.$$variable{'TaxExempt2'}} = 'CHECKED';
		$$variable{'rdbPerfecting'.$$variable{'Perfecting'}} = 'CHECKED';
	} # end if

	# populate drop downs
	$_ = "SELECT lngIndex, strID FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
	$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
	$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
	$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
	$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND dblWidth = '$width'\n" if $width ne '';
	$_ .= "AND dblHeight = '$height'\n" if $height ne '';
	$_ .= "ORDER BY strID";
	$$variable{'ddmPaper'} = ssi::fill_drop_down( $log, $dbh, $_, $index );
	$_ = "SELECT DISTINCT strName, strName FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
	$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
	$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
	$_ .= "ORDER BY strName";
	$$variable{'ddmPaperName'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmPaperName') );
	$_ = "SELECT DISTINCT strCategory,strCategory FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
	$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
	$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
	$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
	$_ .= "ORDER BY strCategory";
	$$variable{'ddmCategory'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmCategory') );
	$_ = "SELECT DISTINCT strFinish,strFinish FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
	$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
	$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
	$_ .= "ORDER BY strFinish";
	$$variable{'ddmFinish'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmFinish') );
	$_ = "SELECT DISTINCT strColour,strColour FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
	$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
	$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
	$_ .= "ORDER BY strColour";
	$$variable{'ddmColour'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmColour') );

	$_ = "SELECT DISTINCT text(dblWidth) || 'x' || text(dblHeight) AS SheetSize, ".
		"text(dblWidth) || 'x' || text(dblHeight) FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
	$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
	$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
	$_ .= "AND strWeight = '" . $r->param('ddmWeight') . "'\n" if $r->param('ddmWeight') ne '';
	$_ .= "ORDER BY SheetSize";
	$$variable{'ddmSheetSize'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmSheetSize') );

	$_ = "SELECT DISTINCT strWeight,strWeight FROM tbl_Paper WHERE 1>0\n";
	$_ .= "AND strCategory = '" . $r->param('ddmCategory') . "'\n" if $r->param('ddmCategory') ne '';
	$_ .= "AND lngPaperListIndex = '" . $r->param('ddmPaperList') . "'\n" if $r->param('ddmPaperList') ne '';
	$_ .= "AND strName = '" . $r->param('ddmPaperName') . "'\n" if $r->param('ddmPaperName') ne '';
	$_ .= "AND strFinish = '" . $r->param('ddmFinish') . "'\n" if $r->param('ddmFinish') ne '';
	$_ .= "AND strColour = '" . $r->param('ddmColour') . "'\n" if $r->param('ddmColour') ne '';
	$_ .= "ORDER BY strWeight";
	$$variable{'ddmWeight'} = ssi::fill_drop_down( $log, $dbh, $_, $r->param('ddmWeight') );

	$_ = "SELECT lngIndex, strName FROM tbl_PaperLists ORDER BY strName";
	$$variable{'ddmPaperList'} = ssi::fill_drop_down( $log, $dbh, $_, $variable->{lngpaperlistindex} );

	$_ = "SELECT lngIndex, strName FROM tbl_ProjectTypes ORDER BY strName";
	my @types = sql::sql_statement( $log, $dbh, $_ );

	$variable->{pid} = $r->param('pid');

	my $pricelists = $dbh->selectall_hashref(q{
			SELECT id, name FROM    pricelist
	},'id',{});


	map {
			my $prices = $dbh->selectall_hashref(q{
					SELECT dblcost, dblmarkup, dblprice,
					   ysndiscountable as discount, lngpaperindex as paper, strunits as units
					FROM   tbl_paper_prices
					WHERE  lngpaperindex = ? AND lnglistindex = ?
			},'paper',{}, $index, $_ );
			my @p;
			map { push @p, $prices->{$_} } keys %{$prices};
			$pricelists->{$_}{prices} = scalar @p ? \@p : [{paper => $index}];

	} keys %{$pricelists} if $index;

	$variable->{PRICELISTS} = $pricelists;


	return OK;
	
} # end sub paper_price_edit

sub paperlist_edit {
    my ( $r, $log, $dbh, $variable ) = @_;
    my ( $temp );

    my $index = $r->param('ddmPaperList');

    if ( $r->param('btnFunction') eq '>>' ) {
        $index = misc::nav_get_next( $r, $log, $dbh, $index, 'lngIndex', 'tbl_PaperLists', '', 'strName' );
    } elsif ( $r->param('btnFunction') eq '<<' ) {
        $index = misc::nav_get_previous( $r, $log, $dbh, $index, 'lngIndex', 'tbl_PaperLists', '', 'strName' );
    } elsif ( $r->param('btnFunction') eq 'Delete' ) {
		$_ = misc::nav_get_next( $r, $log, $dbh, $index, 'lngIndex', 'tbl_PaperLists', '', 'strName' );
		$temp = "DELETE FROM tbl_PaperLists WHERE lngIndex='$index'";
		sql::sql_statement( $log, $dbh, $temp );
		$index = $_;
    } elsif ( $r->param('btnFunction') eq 'Save' ) {
        my @sql = (
			'strDescription',	$r->param('strDescription'),
			'strName',			$r->param('strName')
		);
		
        if ( $index eq '' ) {
            sql::insert( $log, $dbh, 'tbl_PaperLists', @sql );
            $temp = "SELECT lngIndex FROm tbl_PaperLists WHERE strName='" . $r->param('strName') . "'";
            ( $index ) = sql::sql_statement( $log, $dbh, $temp );
        } else {
            sql::update( $log, $dbh, "tbl_PaperLists", "lngIndex='$index'", @sql );
        } # end if
    } # end if

	$_ = "SELECT strDescription, strName FROM tbl_PaperLists WHERE lngIndex = '$index'";
	@$variable{'strDescription', 'strName'} = sql::sql_statement( $log, $dbh, $_ );

    $$variable{'ddmPaper'} = ssi::fill_drop_down( $log, $dbh, $temp, $index . '', 36 );

    $temp = "SELECT DISTINCT lngIndex,strName FROM tbl_PaperLists ORDER BY strName";
    $$variable{'ddmPaperList'} = ssi::fill_drop_down( $log, $dbh, $temp, $index, 36 );
	$$variable{'PaperIndex'} = $index;

    return OK;
} # end sub paperlist_edit

# Given a database handle, write paper information as a CSV file directly to
# the output stream. Simple meaningless 'status' return.
sub export_paper {
    my ($r, $dbh, $variable) = @_;

    # The user can select to either export sheet or roll stock. Default is
    # sheet stock if the type isn't selected.
    my $type = $r->param('type') eq 'roll' ? 'roll' : 'sheet';

    # Select all paper (of chosen type) for export.
    # ew - dirty, dirty, dirty.
    my $query = $type eq 'roll'
        ? q{ SELECT strCategory, strID, strName, strDetails,
                    strFinish, strColour, strMWeight, strWeight, strCalliper,
                    dblWidth, dblrollweight, dblpurchaseunit,
					strTemplate, ysnDoubleSided, lngSort,
                    ( SELECT strName
                      FROM tbl_PaperLists
                      WHERE lngIndex = lngPaperListIndex) AS strsupplier
                    <%REPLACE_ME%>
             FROM tbl_paper_roll t
             ORDER BY strName, strCategory, dblWidth, dblpurchaseunit }
        : q{ SELECT strCategory, strID, strName, strDetails,
                    strFinish, strColour, strMWeight, strWeight, strCalliper,
                    dblWidth, dblHeight, lngPackageQty, ysnBreakable,
                    dblBrokenCartonPrice, dblEndBracketPrice, dbl1TonPrice,
                    dbl5TonPrice, dbl20TonPrice, dblOtherPrice,
                    ( SELECT strName
                      FROM tbl_PaperLists
                      WHERE lngIndex = lngPaperListIndex) AS strsupplier,
                    strTemplate, ysnDoubleSided, ysnCutPaper, lngMultiPart,
                    ysnPerfecting, lngSort, strbaseprice
                    <%REPLACE_ME%>
             FROM tbl_Paper t
             ORDER BY strName, strCategory, dblWidth, dblHeight };

    my $count = $dbh->selectrow_array(q{
        SELECT COUNT(*) FROM paper_specs
    });

    my @replacements;

    if (defined $count && $count > 0) {
        my @columns = @{ $dbh->selectcol_arrayref(q{
            SELECT DISTINCT strname FROM paper_specs
        })};

        foreach my $column (@columns) {
            push (@replacements, qq{
                ( SELECT strvalue FROM paper_specs WHERE strname = '$column'
                AND paper_specs.lngindex = t.lngIndex ) AS $column
            });
        }
    }

    my $replacement_text = scalar @replacements
                         ? ",\n" . join q{,}, @replacements
                         : '';

    $query =~ s/<%REPLACE_ME%>/$replacement_text/;

    my $sth = $dbh->prepare($query);
    $sth->execute;

    # Get the field names from the database for the header.
    my @header = map { s/^(\w{3})(\w)/$1\u$2/; $_ } @{ $sth->{NAME} };

    # The current export function needs a flattened array.
    my @data;
    push @data, @$_ while $_ = $sth->fetch;

    # Export the paper, this function writes the CSV directly to the output
    # stream.
    misc::export_csv(
        $r, $r->log, $variable, "paper-$type.csv", \@header, \@data 
    );

    return OK;
}

sub import_export {
	my ( $r, $log, $dbh, $variable ) = @_;

	# We only show roll stock if they have a web press in their inventory.
	$variable->{has_web} = $dbh->selectrow_array(q{
        SELECT count(*) FROM tbl_equipment WHERE strtype = 'web' 
		                                      OR strtype = 'inkjetprinter' 
    });

	my $list_id = $r->param('ddmPriceList');

	my $query = "SELECT id, currency || '-' || name FROM pricelist";

	$variable->{ddmPriceList} = ssi::fill_drop_down(
        $log, $dbh, $query, $list_id 
    );

	return OK if $r->method ne 'POST';

    # If we're exporting head off there.
    if ( $r->param('export') ) {
        export_paper($r, $dbh, $variable);
        return OK;
    }
    # Not the best of guard clauses but it will do.
    return OK if !$r->param('import');

    # Handler for sending import errors to screen. Horrible little thing but
    # at least it gives some diagnosis. As this is the admin section we can
    # let them see stuff like table and field names.
    local $SIG{__DIE__} = sub {
        my ($err) = @_;
        $r->content_type('text/html; charset=utf-8');
        print q{
            <html><head><title>Error During Import</title></head><body>
            <h2>Error During Import</h2>
            <p>No changes to paper have been made. Please correct the
            following errors and try again.</p>
            <hr />
        }, $err, q{<br /><br /></body></html>} ;
        $r->log_error($err);
    };

    # Error out unless some sort of file has been uploaded.
    if (!defined $r->param('filePaper') || $r->param('filePaper') eq '') {
		 return misc::error(
             $log, $dbh, $variable, 'No file selected.', 
             'You must select a file to import.'
         );
    }
    
    # Retrieve the uploaded data.
    my $content_fh = misc::get_upload_fh( $r, 'filePaper' )
        || die "Failed getting uploaded file!\n";

    my @fields = map { tr/a-zA-Z0-9_//cd; lc $_ } split q{,}, <$content_fh>;

    # Define the types of the fields (string, numeric, integer) of the
    # fields to process.
    my %types = (
        # Fields common to both types.
        strcategory => V,  strid       => V,  strname     => V, 
        strdetails  => V,  strfinish   => V,  strcolour   => V,
        strmweight  => N,  strweight   => V,  strcalliper => N,
        dblwidth    => N,  strsupplier => V,  
        
        recommendations => V, # Deprecated and unused now.

        # Sheet stock only.
        dblheight     => N, lngpackageqty      => I, ysnbreakable         => V,
        dbl1tonprice  => N, dbl5tonprice       => N, dbl20tonprice        => N,
        dblotherprice => V, dblendbracketprice => N, dblbrokencartonprice => N,
        strtemplate   => V, ysndoublesided     => V, ysncutpaper          => V,
        lngmultipart  => I, ysnperfecting      => V, lngsort              => I,

        # Rolls only.
        dblrollweight => N, dblpurchaseunit => I,

        # Large format.
        lngcutdifficulty => I, ysnoutdoor => V, stridentifier => V,
    );
    # Set the types of the fields present in the header (first line).
    my $csv = Text::CSV_XS->new({ 
            binary => 1,                      # Required for UTF-8
            types  => [ @types{ @fields } ],
    });

    # Are we working with sheets or rolls?
    my $table = $r->param('type') eq 'roll' ? 'tbl_paper_roll' : 'tbl_paper';

    my $press_type = $r->param('type') eq 'roll' ? 43 : 14; # Web : Offset

    # Supplier cache so we don't have to do DB lookups every time.
    my %suppliers;

    my @project_types = @{ $dbh->selectcol_arrayref(q{
        SELECT strid FROM tbl_projecttypes
    }) };

    # Start the processing.
    # no warnings qw(numeric);
    local $dbh->{RaiseError} = 0;
    $dbh->begin_work;
    $variable->{message} = '';

    # Check the deletion flag and if it is set we'll just delete all the
    # contents in the table before we start. TODO: Why? Just have one checkbox
    # or name the checkboxes the same this. We only care that they've asked to
    # delete not which damn check box they clicked. Not only that the checkbox
    # won't even exist unless it's been clicked.
    if (   ($table eq 'tbl_paper'      && $r->param('chkDeleteSheets'))
        || ($table eq 'tbl_paper_roll' && $r->param('chkDeleteRolls')) )
    {
		$variable->{predeleted} = 1;
        $dbh->do(qq{
            DELETE FROM tbl_paper_prices
            WHERE lngpaperindex IN (SELECT lngindex FROM $table)
        });

        # This is important since we need to only delete prices for the type
        # of paper we're killing off.
        my $sth = $dbh->prepare("DELETE FROM $table");

        # Putting $table in as a variable surrounds it with ticks and bungs up
        # the query.
        my ($count) = $sth->execute(); 

	$variable->{message} = sprintf(
              "%d %ss of paper marked for deletion prior to insert of"
            . "new paper.<br>",
            $count, $r->param('type')
	);
    }

    my ($count, $err_count, $err_flag) = (0, 0, 0);

    foreach my $line ( <$content_fh> ) {
        $count++;
        my $line_number = $count + 1;

		$log->debug("PROCESSING LINE $line_number");
		$log->debug("PROCESSING LINE Content: $line");
        # Parse the CSV line into fields.
		#$csv->parse($line) or die "Can't parse CSV line: $line\n";
        if ( !$csv->parse($line) ) {
			$err_count++;
			$err_flag++;
			$variable->{message} 
                .= "<p>Can't parse CSV line $line_number: " . $csv->error_input() . "</p>";
			next;
		}
        # Load the line into a hash (slow but worth it).
        my %paper; 
        @paper{ @fields } = $csv->fields();

        # If there are no non-empty values in the line, then we'll skip it cleanly
        if (!join q{}, values %paper) {
            $err_count++;
            $variable->{message} 
                .= "Line $line_number: has no data - skipping blank line."
                 . "<br />";
            next;
		}

        my $has_all     = 1;
        my @large_specs = qw( lngcutdifficulty ysnoutdoor stridentifier );
#
#        $has_all &&= $paper{$large_specs[$_]} ne ''
#            foreach 0 .. scalar(@large_specs) - 1;
#
#        # If it has one of the large format specs, it has to have all of them.
#        foreach my $spec (@large_specs) {
#            if ($paper{$spec} && !$has_all) {
#                $err_count++;
#                $err_flag++;
#
#                $variable->{message}
#                    .= "Line $line_number has $spec but doesn't define
#                        ALL large format parameters.<br />";
#
#                next;
#            }
#        }

        # If it doesn't have an ID, it will be rejected, but will be a cause
        # for error
        if (!$paper{strid}) {
            $err_count++;
            $variable->{message} 
                .= "Line $line_number: contains no strid or is improperly "
                .  "formatted.<br />";

            $err_flag++;
            next;
    	}

	    if ($paper{strid} =~ m{/}) {
            $count++;
            $err_count++;
            $variable->{message} 
                .= "Line $line_number: contains a strid with an invalid "
                .  q{character: "/"<br />};

            $err_flag++;
    	}

		foreach my $f ( qw{ dblwidth	dblheight 
							strcalliper strweight 
							strmweight	strcolour
							strfinish	strname
		}) {
			if ( defined  $paper{$f} && ! $paper{$f} ) { 
				$variable->{message} .= "Line $line_number: missing paper $f <br />";
				$err_count++;
				$err_flag++;
			}
		}

        # RECORD MUNGING
        #
        # If the user has defined a supplier (0 is not a valid supplier).
        my $supplier;

        if ($paper{strsupplier}) {
            # Look our supplier up from the cache.
            $supplier = $suppliers{ $paper{strsupplier} };
            if ( $paper{strsupplier} !~ /^\D/ && $paper{strsupplier} !~ /\D$/) 
            {
                $err_flag++;
                $err_count++;

                $variable->{message} 
                    .= "Line $line_number: A supplier cannot start and end "
                    .  "with a digit.<br />";

                next;
            }

            if (!defined $supplier) {
                # Check if the supplier exists. If the supplier doesn't exists
                # we'll add it and get it's new ID.

                $supplier = $dbh->selectrow_array(q{
                    SELECT lngindex FROM tbl_paperlists where strname = ? 
                }, undef, $paper{strsupplier});

                if (!defined $supplier) {
                    insert($log, $dbh, 'tbl_paperlists', 
                        strname => $paper{strsupplier}
                    );
                    # $supplier = $dbh->last_insert_id(
                    #     undef, undef, 'tbl_paperlists', 'lngindex');
                    $supplier = $dbh->selectrow_array(
                        q{SELECT currval('paperlist_index_seq')}
                    );

					if (!$supplier) {
						$variable->{message} 
                            .= "Supplier '$paper{strsupplier}' could not be "
                             . "added to the database.<br>";
					}
                }
                # Add the supplier to the cache.
                $suppliers{ $paper{strsupplier} } = $supplier;
            }
        }
        
        $paper{lngpaperlistindex} = $supplier; 
        delete $paper{strsupplier};

        # If we currently have any of these 'boolean' fields, clean them
        # up so they's either Y(es), N(o), or undef. If they're NULL they'll
        # default to whatever is set in the database.
        for my $key (
            qw( ysnbreakable ysndoublesided ysncutpaper ysnperfecting
                ysnoutdoor                                            )
        ) {
            next if !exists $paper{$key};

            # we have to be careful to only assign $1 here if the regex
            # matches -- originally it assigned $1 even if it didn't match
            # because $1 kept its value from the last iteration.

            $paper{$key} = $paper{$key} =~ /(Y|N)/i
                         ? uc $1
                         : undef;
        }

		# If any of the numeric fields in the database are currently empty strings
		# then convert them to NULL.
        for my $key
            (qw( lngmultipart  lngpackageqty lngpaperlistindex 
                 dbl20tonprice dbl1tonprice  dblbrokencartonprice 
                 dblotherprice dbl5tonprice  dblendbracketprice   )) 
        { 
            next if !exists $paper{$key};
            $paper{$key} = 0 if $paper{$key} eq '';
		}

        # Project recommendations are stored in a seperate table.
        my @recommendations = split q{,}, $paper{recommendations};
        delete $paper{recommendations};

        # Note that for this to work, our recommendations that are comma
        # seperated have to be within one quoted field of the csv.

        #
 
 		# If we have an error message then we wont' even try to update the 
		# db. Just collect our errors and then spit them back
		# out to the user.
		next if $err_flag;

        # UPDATE PAPER
        #
        # Set the id if the paper exists.
        my $id = $dbh->selectrow_array(qq{
            SELECT lngindex FROM $table WHERE strid = ?
            }, undef, $paper{strid}
        );

        # If we've been given a DELETE command drop this record and delete
        # the paper if it's there.
        if ( $paper{strcategory} =~ /DELETE/i ) {
            if (defined $id) {
                $dbh->do(qq{ DELETE FROM $table 
                             WHERE lngindex = ? }, undef, $id);
                $dbh->do(qq{ DELETE FROM tbl_paper_recommendations 
                             WHERE lngpaperindex = ? }, undef, $id);
            }
            next;
        }

        my %largespecs;
        foreach my $spec (@large_specs) {
            $largespecs{$spec} = $paper{$spec};
            delete $paper{$spec};
        }

        # If the paper doesn't exists add it.
        if (not defined $id) {
			
            sql::insert( $log, $dbh, $table, %paper);

            # $id = $dbh->last_insert_id(undef, undef, $table, 'lngindex');
            $id = $dbh->selectrow_array(q{SELECT currval('material_seq')});
        }                
        # Otherwise update it.
        else {
            sql::update( $log, $dbh, $table, "lngindex = $id", %paper );               
        }

        if ($has_all)
        {
            $dbh->do(
                "DELETE FROM paper_specs WHERE lngindex = ?", undef, $id
            );

            my $sth = $dbh->prepare(
                "INSERT INTO paper_specs (lngindex, strname, strvalue)
                 VALUES (?, ?, ?)"
            );

            foreach my $spec (keys %largespecs)
            {
                $sth->execute($id, $spec, $largespecs{$spec});
            }
        }

		if (!$dbh->selectrow_array(q{SELECT MAX(lngIndex) from tbl_materials}) ) 
        {
			$err_flag++;
			$err_count++;
			$variable->{message} 
                .= "Line $line_number: caused a fatal database error. "
                .  "Paper import terminated<br />";
			last;
		}
        
    }

	if ($err_flag) {
		$variable->{message} 
            .= "Found $err_flag unrecoverable errors - your changes have not "
            .  "been saved. Please fix the above errors and try again.<br />";

		$dbh->rollback;
	}
    else {
		price_list_edit($r, $log, $dbh, $variable);
		$dbh->commit;
	}

    # Return a status message so the user has some feedback. We chould trap
    # errors and use this for them as well?
    if ($count && !$err_flag) {
        $variable->{message} 
            .= sprintf "%d %ss of paper succesfully imported.<br />", 
                ($count - $err_count), $r->param('type');
        $variable->{message} 
            .= sprintf " %d blank/no id records skipped.<br />",
                $err_count if $err_count;

        if ($variable->{predeleted}) {
            $variable->{message} .= "Your stocks have been completely "
                                 .  "refreshed and need repricing. <br />";
        }
    }
    else {
        $variable->{message} .= "No valid records in imported file.<br>" 
            if !$err_flag;
    }

    return OK;
}

sub paperlist_view {
	my ( $r, $log, $dbh, $variable ) = @_;
	my ( $temp );

	$temp = "SELECT lngIndex, strID, strName, strFinish, strColour, strWeight, text(dblWidth) || 'x' || text(dblHeight), dblBrokenCartonPrice, dblEndBracketPrice, dbl1TonPrice, dbl5TonPrice, dbl20TonPrice, dblOtherPrice ".
		"FROM tbl_Paper ".
		"WHERE lngPaperListIndex = '" . $r->param('ddmPaperList') . "'" .
	"ORDER BY strID";
	@{$$variable{'PAPERS'}} = sql::sql_statement( $log, $dbh, $temp );

	return OK;
} # end sub paper_list_view

sub price_list_edit {
    my ( $r, $log, $dbh, $variable ) = @_;
    my $list_id = $r->param('ddmPriceList');
    if ( $r->param('btnFunction') eq '>>' ) { 
        $list_id = misc::nav_get_next( $r, $log, $dbh, $list_id, 'id', 'pricelist',"",'id' );
    } elsif ( $r->param('btnFunction') eq '<<' ) {
        $list_id = misc::nav_get_previous( $r, $log, $dbh, $list_id, 'id', 'pricelist',"",'name' );
    } elsif ( $r->param('btnFunction') eq 'Export Prices' ) {
        if ( $list_id eq '' ) {              
		if ($r->param('import')&& !($variable->{predeleted})) {
			return; # we're not going to error if we can from the definitions page
		}
            return misc::error( $log, $dbh, $variable, 'No pricelist selected.', 'You must select a pricelist before exporting.');                               
        } # end if          
        my $list = $dbh->quote($list_id);
        # Export all papers. If a paper doesn't have a price for that list it
        # will get a 0 price and be displayed at the bottom of the exported
        # CSV (As per Will's request). This is really a stopgap measure that
        # should be properly addressed by database constraints and changing
        # how papers are selected.
        my @header = ( 'Paper ID', 'Min', 'Max', 'Units', 'Cost', 'Markup', 'Price', 'Discountable' );
        my @data = sql::sql_statement( $log, $dbh, qq{
            SELECT p.strid, 
                   r.lngMin, 
                   r.lngMax, 
                   r.strUnits, 
                   '\$'||coalesce(r.dblCost, 0), 
                   coalesce(r.dblMarkup, 0)||'%',
                   '\$'||coalesce(r.dblPrice, 0), 
                   coalesce(r.ysnDiscountable, 'Y')
            FROM ( SELECT lngindex, strid FROM tbl_paper
				   UNION
                   SELECT lngindex, strid FROM tbl_paper_roll
			     ) p FULL JOIN tbl_paper_prices r ON (p.lngindex = r.lngpaperindex)
            WHERE (r.lnglistindex = $list OR r.lnglistindex IS NULL)
            ORDER BY (dblPrice = 0), strid, lngmin
        });
        misc::export_csv( $r, $log, $variable, ($r->param('strName') . '.csv'), \@header, \@data );

    } elsif (($r->param('btnFunction') eq 'Import Prices')||$r->param('import')) {
        #$variable->{message} = ''; #since we're calling from import_export we want to preserve our messages
$log->debug("PAPER: in import prices functionality");
        if ( $list_id eq '' ) {
		if ($r->param('import') && !($variable->{predeleted})) {
			return; #we didn't supply a pricelist so we'll just not do this part now
		}
            return misc::error( $log, $dbh, $variable, 'No pricelist selected.', 'You must select a pricelist before importing.');
        } # end if

        if ( $r->param('filePrices') eq '' ) {
		if ($r->param('import')&& !($variable->{predeleted})) {
			return; # we're not going to error if we can from the definitions page
		}
            return misc::error( $log, $dbh, $variable, 'No file given.', 'You must select a pricing file to import.');
        } # end if

        my $pricelist = new eprint::admin_paper::pricelist( $log, $dbh, $list_id );

# An import replaces the current pricelist, so delete verything in the current one.

# change of design - we're killing all our roll stocks when we import only sheetfed pricing, etc. We want to be
# able to only delete the stocks that are getting replaced with new pricing, so it'll have to be done one row at a time instead of
# a quick and dirty batch delete at the front. - Duke
		#$_ = "DELETE FROM tbl_Paper_Prices WHERE lngListIndex = '$list_id'";
		#sql::sql_statement( $log, $dbh, $_ );
		#replace the above lines with deletes as we skim through content

		# get the upload.
		my @content = misc::get_upload( $r, $log, 'filePrices' );
		# get rid of title line
		shift @content;

		#convert it
		my $csv = Text::CSV_XS->new();

		my $count = 1;

		my %deleted;
		foreach my $line ( @content ) {
			my $status = $csv->parse($line);
			my ( $id, @data ) = $csv->fields();
			next if $id eq '';
			my $index = get_index_by_id( $log, $dbh, $id );
			if ( $index eq '' ) {
				$variable->{message} .= "Line ".($count+1).": Ignoring undefined stock: $id<br>";
				next;
			} # end if
			unless ($deleted{$index}) {
				sql::sql_statement($log,$dbh,"delete from tbl_paper_prices where lngpaperindex='$index' and lnglistindex='$list_id'");
				$deleted{$index} = 1; #we'll delete every stock's prices that we're repricing, but only once for each stock
			}
			my $price_set = $pricelist->getPaperPriceSet( $index );
			my $price = eprint::admin_paper::price->new( $log, $dbh, $price_set );
			$price->set( undef, @data );
			$price_set->addPrice( $price );
			$count++;
		} # end foreach
		$log->debug("PAPER: replaced pricing ... message contains: $variable->{message}");
		$variable->{message} .= "Replaced pricing for ".scalar (keys %deleted)." stocks.<br>";
		$variable->{message} .= "Set pricing for $count items.<br>";
		$pricelist->save();
	} # end if

	my $currency_index;
	if ( $list_id ne '' ) {
		$_ = "SELECT name, description, currency FROM pricelist WHERE id = '$list_id'";
		( @$variable{'strName','strDescription'}, $currency_index ) = sql::sql_statement( $log, $dbh, $_ );
	} # end if
	$_ = "SELECT id, currency || '-' || name FROM pricelist";
	$$variable{'ddmPriceList'} = ssi::fill_drop_down( $log, $dbh, $_, $list_id );

	$_ = "SELECT code, name FROM currency ORDER BY name";
	$$variable{'ddmCurrency'} = ssi::fill_drop_down( $log, $dbh, $_, $currency_index );

	$$variable{'ID'} = $list_id;

	return OK;
} # end sub price_list_edit

sub price_list_view {
    my ( $r, $log, $dbh, $variable ) = @_;

    my $list_index = sql::escape( $r->param('ddmPriceList') );
    $_ = "SELECT currency || '-' || name FROM pricelist WHERE id = '$list_index'";
    @$variable{'PriceListName'} = sql::sql_statement( $log, $dbh, $_ );
    $$variable{'list_id'} = $list_index;

    $_ = "SELECT DISTINCT lngIndex, strName, strID ".
        "FROM tbl_Paper, tbl_Paper_Prices ".
        "WHERE tbl_Paper_Prices.lngListIndex = '$list_index' ".
        "AND lngIndex = lngPaperIndex ".
        "ORDER BY strID";
    @{$$variable{'PRODUCTS'}} = sql::sql_statement( $log, $dbh, $_ );

    for ( my $index = 0; $index < @{$$variable{'PRODUCTS'}}; $index += 3 ) {

        $_ = "SELECT lngMin, lngMax, strUnits, dblCost, dblMarkup, dblPrice\n".
                "FROM tbl_Paper_Prices ".
                "WHERE lngListIndex = '$list_index' ".
                "AND lngPaperIndex = '$$variable{'PRODUCTS'}[$index]'" .
                "ORDER BY lngMax";
        @{$$variable{"PRICES_$$variable{'PRODUCTS'}[$index]"}} = sql::sql_statement( $log, $dbh, $_ );
    } # end for
    return OK;

} # end sub price_list_view

1;



#
# PRICE
#
{ 
    package eprint::admin_paper::price;
    use strict;
    use warnings;

    sub new {
        my ( $type, $log, $dbh, $group ) = @_;

        my $self = {
            log   => $log,
            dbh   => $dbh,
            group => $group, # Watch for cyclic references.
        };

        return bless $self, $type;
    }


    sub save {
        my $self = shift;

        sql::insert( $self->{log}, $self->{dbh}, 'tbl_Paper_Prices',
            lngListIndex    => $self->{group}->{list_index},
            lngPaperIndex   => $self->{group}->{product_index},
            lngMin          => ( $self->{min}          || 'NULL' ),
            lngMax          => ( $self->{max}          || 'NULL' ),
            strUnits        => ( $self->{units}        || 'NULL' ),
            dblCost         => ( $self->{Cost}         || 'NULL' ),
            dblMarkup       => ( $self->{Markup}       || 'NULL' ),
            dblPrice        => ( $self->{Price}        || 'NULL' ),
            ysnDiscountable => ( $self->{Discountable} || 'Y'    ),
        );
    }

    # receives a key, returns the key value from $self if it has a value, or
    # returns a string of NULL if not -- basically just factoring out the
    # map() expression in save().
    sub _replace_null {
        my ($self, $key) = @_;

        return $self->{$key} eq '' ? 'NULL' : $self->{$key};
    }

    sub set {
        my $self = shift;
        setEquipment( $self, shift );
        setMin( $self, shift );
        setMax( $self, shift );
        setUnits( $self, shift );
        setCost( $self, shift );
        setMarkup( $self, shift );
        setPrice( $self, shift );
        setDiscountable( $self, shift );
    }

    sub setDiscountable {
        my $self = shift;
        $self->{Discountable} = shift;
    }
    sub setEquipment {
        my $self = shift;
        $self->{equipment_index} = shift;
    }

    sub setMin {
        my $self = shift;
        $_ = shift;
        #$_ =~ s/[\D\-]//g;
        $self->{min} = $_;
    }

    sub setMax {
        my $self = shift;
        $_ = shift;
        #$_ =~ s/[\D\-]//g;
        $self->{max} = $_;
    }

    sub setUnits {
        my $self = shift;
        $self->{units} = shift;
    }

    sub setCost {
        my $self = shift;
        $_ = shift;
        $_ =~ s/([^\d\.])//g;
        $self->{Cost} = $_;
    }

    sub setMarkup {
        my $self = shift;
        $_ = shift;
        $_ =~ s/\%//g;
        $self->{Markup} = $_;
    }

    sub setPrice {
        my $self = shift;
        $_ = shift;
        $_ =~ s/([^\d\.])//g;
        $self->{Price} = $_;
    }

    sub copy {
        my $self = shift;
        my $src = shift;

        setEquipment( $self, $src->{equipment_index} );
        setMin( $self, $src->{min} );
        setMax( $self, $src->{max} );
        setUnits( $self, $src->{units} );
        setCost( $self, $src->{Cost} );
        setMarkup( $self, $src->{Markup} );
        setPrice( $self, $src->{Price} );
        setDiscountable( $self, $src->{Discountable} );
    }

    1;
}


#
# PRICESET
#
{ 
    package eprint::admin_paper::priceset;
    use strict;

    sub new {
        my ($type, $log, $dbh, $list_index, $product_index, $equipment_index, $qty) = @_;
        
        my $self = {
            'log'           => $log,
            dbh             => $dbh,

            list_index      => $list_index,
            product_index   => $product_index,
            equipment_index => $equipment_index,
            qty             => $qty,
            
            price           => [],
        };
        
        return bless $self, $type;
    }

    sub addPrice {
        my $self = shift;
        my $price = shift;

        push @{$self->{prices}}, $price;
    }

    sub save {
        my $self = shift;

        $_ = "DELETE FROM tbl_Paper_Prices WHERE lngPaperIndex='" . $self->{product_index} . "'\n".
            "AND lngListIndex = '" . $self->{list_index} .  "'\n";
        $_ .= "AND ($self->{qty} :: numeric >= lngMin OR lngMin isNull) AND ($self->{qty} :: numeric <= lngMax OR lngMax isNull)" if $self->{qty};
        sql::sql_statement( $self->{log}, $self->{dbh}, $_ );

        foreach my $price ( @{$self->{prices}} ) {
            $price->save();
        }
    }
}


#
# PRICELIST
#
{
    package eprint::admin_paper::pricelist;
    use strict;

    use sql ();

    sub new {
        my ($class, $log, $dbh, $list_index) = @_;

        return bless { 'log'      => $log,
                        dbh        => $dbh,
                        list_index => $list_index }, $class;
    }

    sub save {
        my $self = shift;

        $self->{log}->debug("Saving Pricelist" );

        # Service and material pricing are not allowed to change through this
        # interface.

        if ( keys %{$self->{paperpricesets}} ) {
            foreach my $product_index ( keys %{$self->{paperpricesets}} ) {
                $self->{paperpricesets}{$product_index}->save();
            }
        }
    }

    sub getPaperPriceSet {
        my $self = shift;
        my $product_index = shift;

        if ( ! $self->{paperpricesets}{$product_index} ) {
            my $price_set = new eprint::admin_paper::priceset( $self->{log}, $self->{dbh}, $self->{list_index}, $product_index );
            addPaperPriceSet( $self, $price_set );
        }
        return $self->{paperpricesets}{$product_index};
    }

    sub addPaperPriceSet {
        my ($self, $priceSet) = @_;
        $self->{paperpricesets}{ $priceSet->{product_index} } = $priceSet;
    }
    
    1;
}
