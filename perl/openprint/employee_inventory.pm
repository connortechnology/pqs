use strict;
package openprint::employee_inventory;
use Authen::Captcha ();
require sql;
require misc;

require openprint::StockPurpose;
require openprint::PaperInventory;
require openprint::StockBrand;
require openprint::StockManufacturer;
require openprint::StockFinish;
require openprint::StockColour;
require openprint::StockQuality;
require openprint::StockPurpose;
require openprint::InventoryCondition;
require openprint::RFIDTag;
require openprint::RFIDTagType;
require openprint::RFIDTagHistory;
require openprint::RFIDScanner;
require openprint::RFIDScannerHistory;
require openprint::Manifest;
require openprint::ManifestContent;
require openprint::Manifest_Content_Type;
require openprint::PaperAllocation;
require openprint::PurchaseOrder;
require openprint::PurchaseOrder_Item;
require openprint::Label;
require openprint::Skid;
require openprint::SkidContent;
require openprint::Claim_Content;
require openprint::Log;
require openprint::Inventory_Check;
require openprint::Inventory_Check_Entry;

use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

use constant DEBUG => 0;
sub skids {
	if ( $param{btnFunction} eq 'move' )	{
		if ( $param{skid_id} ) {
			$param{skid_id} =~ s/[^\d\-\,]//g;
			my @skid_ids;
			foreach my $range ( split ',', $param{skid_id} ) {
				if ( $range =~ /(\d*)\-(\d*)/ ) {
					push @skid_ids, ( $1 .. $2 );
				} else {
					push @skid_ids, $range;
				} # end if
			} # end foreach
			my $Location = new openprint::Location( $param{location_id} );
			if ( ! $Location->id() ) {
				$variable{error} .= 'Invalid location.<br/>';
			} else {
				foreach my $skid_id ( @skid_ids ) {
					my $Skid = new openprint::Skid($skid_id);
					if ( my $e = $Skid->save({location_id=>$param{location_id}}) ) {
						$variable{error} .= "Skid $$Skid{id} has not been moved. Error: $e<br/>";
					} else {
						$variable{information} .= sprintf('<a href="/employee/inventory/skid_details.html?skid_id=%1$d">Skid %1$d</a> has been moved to %2$s.<br/>', $$Skid{id}, $$Location{name} );
					} # end if
				} # end foreach
			} # end if
		} # end if skid_id
	} elsif ( $param{btnFunction} eq 'CheckOut' )   {
		if ( $param{skid_id} ) {
			$param{skid_id} =~ s/[^\d\-\,]//g;
			my @skid_ids;
			foreach my $range ( split ',', $param{skid_id} ) {
				if ( $range =~ /(\d*)\-(\d*)/ ) {
					push @skid_ids, ( $1 .. $2 );
				} else {
					push @skid_ids, $range;
				} # end if
			} # end foreach
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				$Skid->checkout();
			} # end foreach
		} elsif ( $param{skids} ) {
			foreach my $skid_id ( ref $param{skids} eq 'ARRAY' ? @{$param{skids}} : $param{skids} ) {
				my $Skid = new openprint::Skid( $skid_id );
				$Skid->checkout();
			} # end foreach
		} # end if

	} elsif ( $param{btnFunction} eq 'Delete' )	{
		if ( $param{skid_id} ) {
			$param{skid_id} =~ s/[^\d\-\,]//g;
			my @skid_ids;
			foreach my $range ( split ',', $param{skid_id} ) {
				if ( $range =~ /(\d*)\-(\d*)/ ) {
					push @skid_ids, ( $1 .. $2 );
				} else {
					push @skid_ids, $range;
				} # end if
			} # end foreach
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				if ( $Skid->id() ) {
					$variable{error} .= $Skid->delete();
					$variable{information} .= sprintf('<a href="/employee/inventory/skid_details.html?skid_id=%1$d">Skid %1$d</a> has been deleted.<br/>', $$Skid{id} );
					my $PI = new openprint::PaperInventory();
					$variable{error} .= $PI->save({skid_id=>$skid_id, user_id=>$session{user_id}, comment=>'Skid Deleted.'});
				} else {
					$variable{error} .= "Skid $skid_id does not exist in the database.<br/>";
				}
			} # end foreach
		} elsif ( $param{skids} ) {
			foreach my $skid_id ( ref $param{skids} eq 'ARRAY' ? @{$param{skids}} : $param{skids} ) {
				my $Skid = new openprint::Skid( $skid_id );
				if ( $Skid->id() ) {
					$variable{error} .= $Skid->delete();
					$variable{information} .= $Skid->link_to() . ' has been deleted.<br/>';
					my $PI = new openprint::PaperInventory();
					$variable{error} .= $PI->save({skid_id=>$skid_id, user_id=>$session{user_id}, comment=>'Skid Deleted.'});
				} else {
					$variable{error} .= "Skid $skid_id does not exist in the database.<br/>";
				}
				
			} # end foreach
		} # end if
	} elsif ( $param{btnFunction} eq 'Destroy' )	{
		if ( $param{skid_id} ) {
			$param{skid_id} =~ s/[^\d\-\,]//g;
			my @skid_ids;
			foreach my $range ( split ',', $param{skid_id} ) {
				if ( $range =~ /(\d*)\-(\d*)/ ) {
					push @skid_ids, ( $1 .. $2 );
				} else {
					push @skid_ids, $range;
				} # end if
			} # end foreach
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				if ( $_ = $Skid->destroy() ) {
					$variable{error} .= $_;
				} else {
					$variable{information} .= $Skid->link_to() . ' has been destroyed.<br/>';
				} # end if
			} # end foreach
		} elsif ( $param{skids} ) {
			foreach my $skid_id ( ref $param{skids} eq 'ARRAY' ? @{$param{skids}} : $param{skids} ) {
				my $Skid = new openprint::Skid( $skid_id );
				if (!$Skid->deleted()) {
					$variable{information} .= $Skid->link_to() . ' hasn\'t been deleted and so can\'t be destroyed.<br/>';
          next;

				}
        $_ = $Skid->destroy();
        if ( $_ ) {
          $variable{error} .= $_;
        } else {
          $variable{information} .= $Skid->link_to() . ' has been destroyed.<br/>';
        } # end if
			} # end foreach
		} # end if
	} elsif ( $param{btnFunction} eq 'Allocate' ) {
		if ( exists $param{Captcha} ) {
	# Remove spaces, because some people want to put spaces between the characters, etc.
			$param{Captcha} =~ s/\s//g;
			my $Captcha = new Authen::Captcha(
					data_folder => $config{SkinPath}.'/tmp',
					output_folder => $config{SkinPath}.'/images/captcha'
					);
			if ( 1 != $Captcha->check_code( @param{'Captcha','MD5SUM'} ) ) {
				$variable{error} .= 'Captcha Validation Code incorrect.	Please try again.';
				return;
			} # end if
		} # end if
		if ( $param{skid_id} ) {
			$param{skid_id} =~ s/[^\d\,]//g;
			$param{Project} =~ s/\D//g;
			$param{Docket} =~ s/\D//g;

			my $Order = openprint::Order->find_one( docket=>$param{Docket} ) if $param{Docket};
			if ( ( ! $Order ) and $param{Project} ) {
				my $Project = openprint::Project->find_one( 
						( $param{Project} ? ( id=>$param{Project} ) : () ),
						( $param{Docket} ? ( docket=>$param{Docket} ) : () ),
						) if $param{Project} or $param{Docket};
				$Order = $Project->Order() if $Project->order_id();
			} # end if
			if ( ! $Order ) {
				$variable{error} .= 'An invalid Docket or Project # was given. No paper allocated.<br/>';
				return;
			} # end if
			
			my %stocks;
			foreach my $skid_id ( split(',', $param{skid_id} ) ) {
				$skid_id =~ s/\D//g;
				next if ! $skid_id;
				my $Skid = new openprint::Skid( $skid_id );
				foreach my $C ( $Skid->Contents() ) {
					push @{$stocks{$C->paper_id()}}, $Skid;
				} # end foreach Paper
			} # end foreach Skid
			foreach my $paper_id ( keys %stocks ) {
				my $PA = new openprint::Paper( $paper_id )->allocate( $stocks{$paper_id}, $Order->docket() );
				$PA->send_notifications();
			} # end foreach
		} # end if skid_id
	} elsif ( $param{btnFunction} eq 'Download Inventory' ) {
		my ( $header, $data ) = inventory_report( %param );
		my $date = Date::Calc::check_date(@param{'as_of_year','as_of_month','as_of_day'}) ? join('-', @param{'as_of_year','as_of_month','as_of_day'}) : Date::Format::time2str('%Y-%m-%d %H:%M', time);
		my $location = $param{location_id} ? new openprint::Location($param{location_id})->name() : 'All Locations';
		misc::export_csv( $r, $log, \%variable, "PaperInventory $location $date.csv", $header, $data );
	} # end if btnfunction

	$session{'/employee/inventory/skids.html?empty'} = 'N' if ! exists $session{'/employee/inventory/skids.html?empty'};
	$session{'/employee/inventory/skids.html?contents'} = 'Y' if ! exists $session{'/employee/inventory/skids.html?contents'};
	$session{'/employee/inventory/skids.html?hasmanifest'} = '' if ! exists $session{'/employee/inventory/skids.html?hasmanifest'};
	$session{'/employee/inventory/skids.html?hasmanufacturers'} = '' if ! exists $session{'/employee/inventory/skids.html?hasmanufacturers'};
	$session{'/employee/inventory/skids.html?checked_out'} = '' if ! exists $session{'/employee/inventory/skids.html?checked_out'};

	ssi::setup_date_select( '/employee/inventory/skids.html', 'received_on_start', 0 );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'received_on_end', -7 );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'created_on_start', '' );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'created_on_end', '' );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'updated_on_start', '' );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'updated_on_end', '' );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'last_seen_start', '' );
	ssi::setup_date_select( '/employee/inventory/skids.html', 'last_seen_end', '' );

	_skids_results();
	$session{'/employee/inventory/skids.html?rfid'} = '' if ! defined $session{'/employee/inventory/skids.html?rfid'};
	$session{'/employee/inventory/skids.html?rfid_valid'} = '' if ! defined $session{'/employee/inventory/skids.html?rfid_valid'};
	$session{'/employee/inventory/skids.html?hasmanifest'} = '' if ! defined $session{'/employee/inventory/skids.html?hasmanifest'};
	$session{'/employee/inventory/skids.html?type'} = 'Sheet,Roll,Unknown' if ! defined $session{'/employee/inventory/skids.html?type'};
	$session{'/employee/inventory/skids.html?deleted'} = '0' if ! exists $session{'/employee/inventory/skids.html?deleted'};
 
} # end sub skids

sub inventory_report {
	my %param = @_;
	my @header = ('Paper ID','Type','Owner','Manufacturer','Name','Finish','Colour','Weight','Material','Group','Width','Height','Quality', 'MWeight','GSM','Skid#','RFIDTag #','Received On', 'Date Added','Last Updated', 'Location', 'In Stock (sheets)','In Stock(lbs)', 'Condition', 'Last Seen', 'Cost', 'Value', 'Allocated to Docket', 'Dockets' );

	my @data;
	my $count = 0;
	my $total_weight = 0;

	my @location_ids = ();
	if ( $param{location_id} ) {
		my @Locations = openprint::Location->find(id=>[ map { split(',', $_ ) } ( (ref $param{location_id} eq 'ARRAY') ? @{$param{location_id}} : ( $param{location_id} ) ) ] );
		@location_ids = map { $$_{id} } map { $_, $_->get_all_children() } @Locations;
	} else {
		openprint::Location->find( company_id=>$openprint::Owner->id(), type=>'place' );
	}

	my @Stocks;
	my %stock_ids;

	my %sql = (
			( $param{fsc_code} ? ( fsc_code  =>  $param{fsc_code} ) : () ),
			( $param{width} ? ( ($param{OrLarger} ? 'width >=' : 'width') => $param{width} ) : () ),
			( $param{height} ? ( ($param{OrLarger} ? 'height >=' : 'height') => $param{height} ) : () ),
			);

	foreach my $filter ( 'owner_id','manufacturer_id','brand_id','finish_id','colour_id','weight_id','group_id','quality_id','material_id','type' ) {
		next if ! $param{$filter};
		if ( $param{$filter.'_id_exclude'} ) {
			$sql{$filter.' !='} = $param{$filter};
		} else {
			$sql{$filter} = $param{$filter};
		} # end if
	} # end foreach filter
	if ( %sql ) {
		@Stocks = openprint::Paper->find(%sql);
		%stock_ids = map { $_->id(), $_ } @Stocks;
		openprint::StockBrand->find(); # How many can there be?  Just load them all. id => [ map { $_->brand_id() } @Stocks ] );
	} else {
		$log->debug('Not loading stocks');
	} # end if

	my @Skids = openprint::Skid->find(
				( $param{skid_ids} ? ( id=> ( ref $param{skid_ids} eq 'ARRAY' ? $param{skid_ids} : [ split(',', $param{skid_ids} ) ] ) ) : () ),
				#( %stock_ids ? ( 'paper_id &&'=> [ keys %stock_ids ] ) : () ),
				ssi::date_filter( 'added_on_start', 'created_on >=', \%param ),
				ssi::date_filter( 'added_on_end', 'created_on <=', \%param ),
				( @location_ids ? ( location_id=>\@location_ids ) : () ),
				( ( $param{as_of_year} and $param{as_of_month} and $param{as_of_day} ) ?
# Is we are doing rollback, can't use current values
					(
					 ssi::date_filter( 'as_of', 'created_on <=', \%param ),
					) :
					(
#in_stock is used in available_paper and empty is used in skids
					 ( $param{in_stock} ne '' ? ( $param{in_stock} eq '1' ? ( 'quantity >='=>1 ) : ( 'quantity is null or ='=>0 ) ) : () ),
					 ( exists $param{empty} ? ( $param{empty} eq 'Y' ? ( 'quantity is null or ='=>0 ) : ( 'quantity >'=>0 ) ) : () ),
					)
				),
				( $param{type} ? ( 'type is null or in'=>[ ref $param{type} eq 'ARRAY' ? @{$param{type}} : $param{type} ] ) : () ),
			);
	$log->debug('# of Skids: ' . @Skids );
#openprint::RFIDTag->find(id=>[ map { $_->rfidtag_id() ? $_->rfidtag_id() : () } @Skids] );

	my @skid_ids = map { $$_{id} } @Skids;
	my %SkidContents;
	#foreach my $SC ( openprint::SkidContent->find( skid_id => \@skid_ids ) ) {
		#push @{$SkidContents{$$SC{skid_id}}}, $SC;
	#} # end foreach SC

	my %Allocations;
	foreach my $Allocation ( openprint::PaperAllocation->find( 'skid_ids !=' => [] ) ) {
		foreach my $skid_id ( @{$Allocation->skid_ids()} ) {
			$Allocations{$skid_id} = [] if ! $Allocations{$skid_id};
			push @{$Allocations{$skid_id}}, $Allocation->docket();
		}
	}

	my @PIs_to_rollback;
	my %PIs_to_rollback;
	if ( $param{as_of_year} and $param{as_of_month} and $param{as_of_day} ) {
		if ( Date::Calc::check_date(@param{qw( as_of_year as_of_month as_of_day)}) ) {
 
			my $as_of_dt = DateTime->new(
					year       => $param{as_of_year},
					month      => $param{as_of_month},
					day        => $param{as_of_day},
					hour       => 0,
					minute     => 0,
					second     => 0,
					nanosecond => 0,
					time_zone  => $openprint::TZ,
					);
			@PIs_to_rollback = openprint::PaperInventory->find('updated_on >='=>DateTime::Format::Pg->format_datetime($as_of_dt), order=>'id desc');
			%PIs_to_rollback = misc::make_hash_from_array(skid_id=>@PIs_to_rollback);
			$log->debug('Number of PIs to rollback: ' . scalar @PIs_to_rollback);
		} else {
			$variable{error} .= 'Invalid as of date';
		}
	}

	my $total_value = 0;
	foreach my $Skid ( @Skids ) {
		$Skid->Contents( $SkidContents{$$Skid{id}} );
		if ( ! $$Skid{type} ) {
			$Skid->save({type=>undef});
		}
		foreach my $C ( $Skid->Contents() ) {
			next if ! $C;

			if ( $PIs_to_rollback{$$Skid{id}} ) {
				$log->debug("Have PIs to rollback for skid $$Skid{id}");
				foreach my $PI ( @{$PIs_to_rollback{$$Skid{id}}} ) {
					if ( $$PI{paper_id} == $$C{paper_id} ) {
$log->debug("Rolling back quantity on skid $$Skid{id} from $$C{quantity} by $$PI{delta}");
						$$C{quantity} -= $$PI{delta};
					}
				}
			}
			if ( $param{in_stock} eq '1' and ! $C->quantity() ) {
				$log->debug("Skid $$Skid{id} skipped because no quantity") if DEBUG;
				next;
			}
			if ( $param{empty} eq 'Y' and ( $C->quantity() > 0 ) ) {
				$log->debug("Skid $$Skid{id} skipped because we want empty") if DEBUG;
				next;
			}
			if ( $param{empty} eq 'N' and ( $C->quantity() <= 0 ) ) {
				$log->debug("Skid $$Skid{id} skipped because we don't want empty") if DEBUG;
				next;
			}
			if ( defined($param{has_value}) ) {
				if ( $param{has_value} eq '1' and ! $C->cost() ) {
					$log->debug("Skid $$Skid{id} skipped because no cost") if DEBUG;
					next ;
				}
				if ( $param{has_value} eq '0' and $C->cost() ) {
					$log->debug("Skid $$Skid{id} skipped because has cost") if DEBUG;
					next ;
				}
			}

			my $Paper = $C->Paper();
			my $weight = 0;
			if ( $Paper->type() eq 'Roll' ) {
				$weight = $C->quantity();
			} elsif ( $Paper->type() eq 'Sheet' ) {
				$weight += $Paper->sheet_weight() * $C->quantity();
			} else {
				$log->error('Unknown stock type! '.$Paper->to_string());
			} # end if
			$total_weight += $weight;
			$count += 1;
			push @data,(
					$$Paper{id},
					$Skid->type(),
					new openprint::Company($Paper->owner_id())->name(),
					$Paper->manufacturer(),
					$Paper->brand(),
					$Paper->finish(),
					$Paper->colour(),
					$Paper->weight(),
					$Paper->material(),
					$Paper->group(),
					$Paper->width(),
					$Paper->height(),
					$Paper->quality(),
					$Paper->mweight(),
					$Paper->gsm(),
					$$Skid{id},
					$Skid->RFIDTag()->id_short(),
					ssi::format_csv_date( $$Skid{received_on} ),
					ssi::format_csv_date( $$Skid{created_on} ),
					ssi::format_csv_date( $$Skid{updated_on} ),
					$Skid->Location()->name(),
					$Paper->type() eq 'Sheet' ? $C->quantity() : '',
					Math::Round::nearest(0.01, $weight),
					$C->condition(),
					ssi::format_csv_date( $Skid->updated_on() ),#FIXME
					1*$C->cost(),
					1*$C->value(),
					( $Allocations{$Skid->id} ? join(',', @{$Allocations{$Skid->id}}) : '' ),
					join(',', $Skid->dockets() ),
					);
			$total_value += $C->value() if $C->value();
		} # end foreach C
	} # end foreach Skid
	my $date = Date::Format::time2str('%Y-%m-%d %H:%M', time );
	push @data, ( 'Report generated',$date,'Count:',$count,undef,undef,undef,undef, undef,undef,undef, undef, undef, undef, undef, undef, undef, undef, undef, undef,undef,
			'Total Weight (lbs):', Math::Round::nearest(0.01, $total_weight), undef, undef, undef, $total_value, undef, undef );
	return ( \@header, \@data );
} # end sub inventory_report

sub paper {
	if ( $param{btnFunction} eq 'Consumption Report' ) {
		my @header = ('Date','Operator','Owner','Brand','Finish','Colour','Weight','Width','Height','Quality', 'MWeight','GSM','Skid#','Amount','Comment');
		my @data;
		my @inventory = openprint::PaperInventory->find(
				ssi::date_filter( 'added_on_start', 'updated_on >=', \%param ),
				ssi::date_filter( 'added_on_end', 'updated_on <=', \%param ),
				order=>'updated_on',
		);
		foreach my $I ( @inventory ) {
			my $Paper = $I->Paper();
			push @data, 
Date::Format::time2str('%Y-%m-%d %H:%M', Date::Parse::str2time($I->updated_on())),
				$I->User()->name(),
				$Paper->Owner()->name(),
				$Paper->brand(),
				$Paper->finish(),
				$Paper->colour(),
				$Paper->weight(),
				$Paper->width(),
				$Paper->height(),
				$Paper->quality(),
				$Paper->mweight(),
				$Paper->gsm(),
				$I->skid_id(),
				$I->delta . $I->units,
				$I->comment;
		} # end while
		my $date = Date::Format::time2str('%Y-%m-%d %H:%M', time );
		push @data, ( 'Report generated',$date,undef,undef,undef,undef, undef, undef, undef, undef, undef, undef );
		misc::export_csv( $r, $log, \%variable, "PaperConsumption $date.csv", \@header, \@data );
	} elsif ( $param{btnFunction} eq 'Download Log' ) {

		my @header = ('Date','Operator','Owner','Brand','Finish','Colour','Weight','Width','Height','Quality', 'MWeight','GSM','Skid#','Amount','Comment');
		my @info = sql::execute( $log, $dbh, q{SELECT paper_id, skid_id, user_id, delta, units, updated_on, comment FROM paper_inventory ORDER BY updated_on DESC} );
		my @data;
		while ( my ( $paper_id, $skid_id, $user_id, $delta, $units, $time, $comment ) = splice @info, 0, 7 ) {
			my $Paper = new openprint::Paper( $paper_id );
			push @data, $time, new openprint::User($user_id)->name(),
				 new openprint::Company($Paper->owner_id())->name(),
				 $Paper->brand(),
				 $Paper->finish(),
				 $Paper->colour(),
				 $Paper->weight(),
				 $Paper->width(),
				 $Paper->height(),
				 $Paper->quality(),
				 $Paper->mweight(),
				 $Paper->gsm(),
				 $skid_id,
				 $delta . $units,
				 $comment;
		} # end while
		my $date = Date::Format::time2str('%Y-%m-%d %H:%M', time );
		push @data, ( 'Report generated',$date,undef,undef,undef,undef, undef, undef, undef, undef, undef, undef );
		misc::export_csv( $r, $log, \%variable, "PaperInventoryLog $date.csv", \@header, \@data );
	} elsif ( $param{btnFunction} eq 'Download Inventory' ) {
		my ( $header, $data ) = inventory_report( %param );
		my $date = Date::Format::time2str('%Y-%m-%d %H:%M', time );
		my $location = $param{location_id} ? new openprint::Location($param{location_id})->name() : 'All Locations';
		misc::export_csv( $r, $log, \%variable, "PaperInventory $location $date.csv", $header, $data );

	} elsif ( $param{btnFunction} eq 'Delete' ) {
		if ( $param{paper_id} ) {
			my $Paper = new openprint::Paper( $param{paper_id} );
			$Paper->delete();
			$variable{information} .= "Paper $$Paper{id} has been deleted.";
		} elsif ( $param{papers} ) {
			my $ac = sql::start_transaction( undef );		
			my @Papers = openprint::Paper->find( id => $param{papers} );
			foreach my $Paper ( @Papers ) {
				$Paper->delete();
			} # end foreach
			sql::end_transaction( undef, $ac );
			$variable{information} .= @Papers . ' Papers have been deleted.';
		} # end if

	} elsif ( $param{btnFunction} eq 'Save' ) {
		foreach my $key ( keys %param ) {
			if ( $key =~ /txtInStock(\d*)/ ) {
				my $paper_index = $1;
				my $delta = 0;
				my ( $instock ) = sql::execute( $log, $dbh, 'SELECT InStock FROM Paper_Inventory WHERE PaperIndex=? AND updated_on = (SELECT MAX(updated_on) FROM Paper_Inventory WHERE PaperIndex=?)', $paper_index, $paper_index );
				if ( $param{$key} =~ /[\-\+]\d*/ ) {
					$delta = $param{$key};
				} else {
					$delta = $param{$key} - $instock;
				} # end if
				if ( $delta != 0 ) {
					my $PI = new openprint::Paper_Inventory();
					$variable{error} .= $PI->save({
						paper_id	=>	$paper_index,
						instock		=>	$instock + $delta,
						delta		=>	$delta,
						user_id		=>	$session{user_id},
						comment		=>	'Stock Check',
						});
				} # end if

			} # end if
		} # end foreach
	} # end if

	_paper_results();
	$session{'/employee/inventory/paper.html?owner_id_exclude'} = $param{owner_id_exclude} if exists $param{owner_id};
    $session{'/employee/inventory/paper.html?type'} = 'Roll,Sheet' if ! exists $session{'/employee/inventory/paper.html?type'};
	ssi::setup_date_select( '/employee/inventory/paper.html', 'added_on_start', -365 );
	ssi::setup_date_select( '/employee/inventory/paper.html', 'added_on_end', '' );
	$session{'/employee/inventory/paper.html?in_stock'} = '' if ! $session{'/employee/inventory/paper.html?in_stock'};

} # end sub paper

sub _paper_results {
	ssi::save_params( '/employee/inventory/paper.html', ( 
				'manufacturer_id','brand_id','finish_id','colour_id','weight_id','quality_id', 
				'type','owner_id','material_id','group_id', 'condition_id',
				( map { 'added_on_start_'.$_ } ( 'year','month','day' ) ),
				( map { 'added_on_end_'.$_ } ( 'year','month','day' ) ),
				'Docket','fsc_code','width','height','OrLarger','in_stock','owner_id_exclude','allocated','has_value',
			) );
	$session{'/employee/inventory/paper.html?owner_id_exclude'} = $param{owner_id_exclude} if exists $param{owner_id};
	$session{'/employee/inventory/paper.html?OrLarger'} = $param{OrLarger};
} # end sub _paper_results

sub paper_details {
	my $Paper = $variable{Paper} = new openprint::Paper( $param{paper_id} );
	if ( ! $$Paper{id} ) {
		$variable{error} .= "Paper $param{paper_id} not found.\n";
		return;
	} # end if
	if ( $param{btnFunction} eq 'Previous' ) {
		$Paper = $Paper->previous();
	} elsif ( $param{btnFunction} eq 'Next' ) {
		$Paper = $Paper->next();
	} elsif ( $param{btnFunction} eq 'Save' ) {
		$Paper->owner_id( $param{Owner} );
		foreach my $option ( 'Manufacturer', 'Group', 'Brand','Finish','Colour','Weight','Quality' ) {
			my $option_lc = lc $option;
			my $option_id = $option_lc.'_id';
			if ( $param{'txt'.$option} ) {
				$param{$option_lc} = $param{'txt'.$option};
				delete $param{'txt'.$option};
			} elsif ( $param{$option} ) {
				$param{$option_id} = $param{$option};
				delete $param{$option};
			} # end if
		} # end foreach

		my @changes = $Paper->changes( \%param );
		$Paper->set( \%param );
			
		if ( $param{type} eq 'Roll' ) {
			$Paper->height( undef );
		} # end if
		$Paper->mweight( $param{mweight} ) if $param{mweight};
		$Paper->basis_mweight( $param{basis_weight} ) if exists $param{basis_weight};
		if ( exists $param{manufacturers_name} ) {
			s/^\s+//, s/\s+$//, s/\s+/ /g for $param{manufacturers_name};
			$Paper->manufacturers_name( $param{manufacturers_name} );
		} # end if
		$Paper->calliper( $param{calliper} );
		if ( ! $param{paper_id} ) {
			my @papers = openprint::Paper->find(
					( $param{Owner} ? ( owner_id	=>	$param{Owner} ) : () ),
					( $param{txtManufacturer} ? ( manufacturer		=>	$param{txtManufacturer} ) : () ),
					( $param{Manufacturer} ? ( manufacturer_id	=>	$param{Manufacturer} ) : () ),
					( $param{txtBrand} ? ( brand		=>	$param{txtBrand} ) : () ),
					( $param{Brand} ? ( brand_id	=>	$param{Brand} ) : () ),
					( $param{txtFinish} ? ( finish	=>	$param{txtFinish} ) : () ),
					( $param{Finish} ? ( finish_id =>	$param{Finish} ) : () ),
					( $param{txtColour} ? ( colour	=>	$param{txtColour} ) : () ),
					( $param{Colour} ? ( colour_id =>	$param{Colour} ) : () ),
					( $param{txtWeight} ? ( weight	=>	$param{txtWeight} ) : () ),
					( $param{Weight} ? ( weight_id =>	$param{Weight} ) : () ),
					( $param{txtQuality} ? ( quality	=>	$param{txtQuality} ) : () ),
					( $param{Quality} ? ( quality_id=>	$param{Quality} ) : () ),
					( $param{width} ? ( width		=> $param{width} ) : () ),
					( $param{height} ? ( height	=>	$param{height} ) : () ),
					);
			if ( @papers ) {
				$variable{error} .= qq`A paper matching those parameters already exists. Click here to edit it: <a href="paper_details.html?paper_id=$papers[0]{id}">paper $papers[0]{id}</a>`;
				$variable{Paper} = $Paper;
				return;
			} # end if
		} # end if
		if ( ! ( $variable{error} .= $Paper->save() ) ) {
			$variable{information} .= 'Paper successfully saved.<br/>';
			my $PI = new openprint::PaperInventory();
			$PI->save({
					paper_id    =>  $$Paper{id},
					user_id     =>  $openprint::session{user_id},
					poindex     =>  undef,
					instock     =>  $Paper->in_stock(),
					});
			if ( @changes ) {
				(new openprint::Log())->save({Object=>$Paper, action=>'Edit', note=>join(', ', @changes)});
			}
		} # end if
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		if ( ! ( $variable{error} .= $Paper->delete() ) ) {
			$variable{information} .= 'Paper successfully deleted.<br/>';
		} # end if
	} elsif ( $param{btnFunction} eq 'Allocate' ) {
		if ( exists $param{Captcha} ) {
	# Remove spaces, because some people want to put spaces between the characters, etc.
			$param{Captcha} =~ s/\s//g;
			my $Captcha = new Authen::Captcha(
					data_folder => $config{SkinPath}.'/tmp',
					output_folder => $config{SkinPath}.'/images/captcha'
					);
			if ( 1 != $Captcha->check_code( @param{'Captcha','MD5SUM'} ) ) {
				$variable{error} .= 'Captcha Validation Code incorrect.	Please try again.';
				return;
			} # end if
		} # end if
		foreach my $condition_id ( sets::union( map { $_->condition_id() } openprint::SkidContent->find(paper_id=>$param{paper_id},deleted=>0,
						( $param{skid_id} ? ( skid_id=>$param{skid_id} ) : () ),'quantity >' =>0 ) ) ) {
			next if ! $param{'quantity-'.$condition_id};
			allocate( @param{'skid_id','paper_id','quantity-'.$condition_id,'Project','Docket','specific','reason'}, $condition_id );
		} # end foreach condition
		@session{'error','warning','information'} = @variable{'error','warning','information'};
		$variable{ExternalRedirect} = '/employee/inventory/paper_details.html?paper_id='.$Paper->id();
		%param = ();
		return;
	} elsif ( $param{btnFunction} eq 'CheckOut' ) {
		check_out( undef, @param{'paper_id','Quantity','Project','Docket','reason'} );
	} elsif ( $param{btnFunction} eq 'Merge' ) {
		if ( ! $Paper->id() ) {
			$variable{error} .= 'Cant merge.  No given stock.';
			return;
		} # end if
		my @Duplicates = openprint::Paper->find(
				manufacturer_id	=> $Paper->manufacturer_id(),
				brand_id			=> $Paper->brand_id(),
				finish_id			=> $Paper->finish_id(),
				colour_id			=> $Paper->colour_id(),
				weight_id			=> $Paper->weight_id(),
				quality_id		=> $Paper->quality_id(),
				width				=> $Paper->width(),
				height			=> $Paper->height(),
				fsc_code			=>	$Paper->fsc_code(),
				);

		foreach my $Duplicate ( @Duplicates ) {
			next if $Duplicate->id() == $Paper->id();
			$Paper->merge( $Duplicate );
		} # end foreach
		$variable{ExternalRedirect} = '/employee/inventory/paper_details.html?paper_id='.$Paper->id();
	} # end if
	$variable{Paper} = $Paper;
	$variable{paper_id} = $$Paper{id};
} # end sub paper_details

sub save_Paper {
	my ( $id ) = @_;

	if ( $param{'calliper'.$id} > 1 ) {
		$param{'calliper'.$id} /= 1000;
	} # end if

	my $weight;
	if ( $param{'txtWeight'.$id} ) {
		$weight = $param{'txtWeight'.$id};
	} elsif ( $param{'weight'.$id} ) {
		if ( $param{'weight'.$id} =~ /([\d\.]+)PT/i ) {
			$param{'calliper'.$id} = $1 if ! $param{'calliper'.$id};
			$weight = '';
		} else {
			$weight = $param{'weight'.$id};
			$weight .= 'lb' if ! ( $param{'weight'.$id} =~ /lb/ );
		} # end if
	} elsif ( $param{'calliper'.$id} ) {
		if ( $param{'calliper'.$id} > 1 ) {
			$weight = $param{'calliper'.$id}.'PT';
			$param{'calliper'.$id} /= 1000;
		} else {
			$weight = ($param{'calliper'.$id}*1000).'PT';
		}
	} # end if

	my @Papers = openprint::Paper->find(
			( $param{'owner_id'.$id} ? ( owner_id	=>	$param{'owner_id'.$id} ) : () ),
			( $param{'Owner'.$id} ? ( owner_id	=>	$param{'Owner'.$id} ) : () ),
			( $param{'group_id'.$id} ? ( group_id	=>	$param{'group_id'.$id} ) : () ),
			( $param{'Group'.$id} ? ( group_id	=>	$param{'Group'.$id} ) : () ),
			( $param{'txtGroup'.$id} ? ( group		=>	$param{'txtGroup'.$id} ) : () ),
			( $param{'group'.$id} ? ( group		=>	$param{'group'.$id} ) : () ),
			( $param{'manufacturer_id'.$id} ? ( manufacturer_id	=>	$param{'manufacturer_id'.$id} ) : () ),
			( $param{'Manufacturer'.$id} ? ( manufacturer_id	=>	$param{'Manufacturer'.$id} ) : () ),
			( $param{'txtManufacturer'.$id} ? ( manufacturer		=>	$param{'txtManufacturer'.$id} ) : () ),
			( $param{'manufacturer'.$id} ? ( manufacturer		=>	$param{'manufacturer'.$id} ) : () ),
			( $param{'brand_id'.$id} ? ( brand_id	=>	$param{'brand_id'.$id} ) : () ),
			( $param{'Brand'.$id} ? ( brand_id	=>	$param{'Brand'.$id} ) : () ),
			( $param{'txtBrand'.$id} ? ( brand		=>	$param{'txtBrand'.$id} ) : () ),
			( $param{'brand'.$id} ? ( brand		=>	$param{'brand'.$id} ) : () ),
			( $param{'Finish'.$id} ? ( finish_id =>	$param{'Finish'.$id} ) : () ),
			( $param{'finish_id'.$id} ? ( finish_id =>	$param{'finish_id'.$id} ) : () ),
			( $param{'txtFinish'.$id} ? ( finish	=>	$param{'txtFinish'.$id} ) : () ),
			( $param{'finish'.$id} ? ( finish	=>	$param{'finish'.$id} ) : () ),
			( $param{'colour_id'.$id} ? ( colour_id =>	$param{'colour_id'.$id} ) : () ),
			( $param{'Colour'.$id} ? ( colour_id =>	$param{'Colour'.$id} ) : () ),
			( $param{'txtColour'.$id} ? ( colour	=>	$param{'txtColour'.$id} ) : () ),
			( $param{'colour'.$id} ? ( colour	=>	$param{'colour'.$id} ) : () ),
			( $param{'weight_id'.$id} ? ( weight_id =>	$param{'weight_id'.$id} ) : () ),
			( $param{'Weight'.$id} ? ( weight_id =>	$param{'Weight'.$id} ) : () ),
			( $weight ? ( weight=>$weight ) : () ),
# We might 
			( $param{'material_id'.$id} ? ( material_id =>	$param{'material_id'.$id} ) : () ),
			( $param{'material'.$id} ? ( material	=>	$param{'material'.$id} ) : () ),
			( $param{'quality_id'.$id} ? ( quality_id =>	$param{'quality_id'.$id} ) : () ),
			( $param{'quality'.$id} ? ( quality	=>	$param{'quality'.$id} ) : () ),
			( $param{'width'.$id} ? ( width		=> $param{'width'.$id} ) : () ),
			( $param{'height'.$id} ? ( height	=>	$param{'type'.$id} ne 'Roll' ? $param{'height'.$id} : undef ) : () ),
			( $param{'type'.$id} ? ( type		=>	$param{'type'.$id} ) : () ),
			( $param{'calliper'.$id} ? ( 'calliper is null or ='	=>	$param{'calliper'.$id} ) : () ),
			( $param{'fsc_code'.$id} ? ( fsc_code	=>	$param{'fsc_code'.$id} ) : ( 'fsc_code is null or =' => $param{'fsc_code'.$id} ) ),
			);
	my $Paper;

# Paper not found, this is the first time we are adding it to the skid
	if ( 0 == @Papers ) {
		$Paper = new openprint::Paper( );
		$Paper->owner_id( $param{'Owner'.$id} ) if $param{'Owner'.$id};
		$Paper->owner_id( $param{'owner_id'.$id} ) if $param{'owner_id'.$id};
		$Paper->group( $param{'txtGroup'.$id} ) if $param{'txtGroup'.$id};
		$Paper->group( $param{'group'.$id} ) if $param{'group'.$id};
		$Paper->group_id( $param{'Group'.$id} ) if $param{'Group'.$id};
		$Paper->group_id( $param{'group_id'.$id} ) if $param{'group_id'.$id};
		$Paper->manufacturer( $param{'txtManufacturer'.$id} ) if $param{'txtManufacturer'.$id};
		$Paper->manufacturer( $param{'manufacturer'.$id} ) if $param{'manufacturer'.$id};
		$Paper->manufacturer_id( $param{'Manufacturer'.$id} ) if $param{'Manufacturer'.$id};
		$Paper->manufacturer_id( $param{'manufacturer_id'.$id} ) if $param{'manufacturer_id'.$id};
		$Paper->brand( $param{'txtBrand'.$id} ) if $param{'txtBrand'.$id};
		$Paper->brand( $param{'brand'.$id} ) if $param{'brand'.$id};
		$Paper->brand_id( $param{'Brand'.$id} ) if $param{'Brand'.$id};
		$Paper->brand_id( $param{'brand_id'.$id} ) if $param{'brand_id'.$id};
		$Paper->finish( $param{'txtFinish'.$id} ) if $param{'txtFinish'.$id};
		$Paper->finish( $param{'finish'.$id} ) if $param{'finish'.$id};
		$Paper->finish_id( $param{'Finish'.$id} ) if $param{'Finish'.$id};
		$Paper->finish_id( $param{'finish_id'.$id} ) if $param{'finish_id'.$id};
		$Paper->colour( $param{'txtColour'.$id} ) if $param{'txtColour'.$id};
		$Paper->colour( $param{'colour'.$id} ) if $param{'colour'.$id};
		$Paper->colour_id( $param{'Colour'.$id} ) if $param{'Colour'.$id};
		$Paper->colour_id( $param{'colour_id'.$id} ) if $param{'colour_id'.$id};
		$Paper->weight( $weight ) if $weight;
		$Paper->weight_id( $param{'Weight'.$id} ) if $param{'Weight'.$id};
		$Paper->weight_id( $param{'weight_id'.$id} ) if $param{'weight_id'.$id};
		$Paper->quality( $param{'txtQuality'.$id} ) if $param{'txtQuality'.$id};
		$Paper->quality( $param{'quality'.$id} ) if $param{'quality'.$id};
		$Paper->quality_id( $param{'Quality'.$id} ) if $param{'Quality'.$id};
		$Paper->quality_id( $param{'quality_id'.$id} ) if $param{'quality_id'.$id};
		$Paper->material( $param{'material'.$id} ) if $param{'material'.$id};
		$Paper->material_id( $param{'material_id'.$id} ) if $param{'material_id'.$id};
		$Paper->type( $param{'type'.$id} );
		$Paper->fsc_code( $param{'fsc_code'.$id} );
		if ( $param{'type'.$id} eq 'Roll' ) {
			$Paper->width( $param{'width'.$id} );
			$Paper->height( undef );
		} else { #Sheet
			$Paper->width( $param{'width'.$id} );
			$Paper->height( $param{'height'.$id} );
		} # end if
		if ( $weight =~ /^([\d\.]+)lb$/i ) {
			$Paper->basis_mweight($1 * 2);
		} elsif ( $param{'basis_weight'.$id} ) {
			$Paper->basis_mweight( $param{'basis_weight'.$id} );
		} # end if
		$Paper->calliper( $param{'calliper'.$id} ) if $param{'calliper'.$id} ;
		$Paper->mweight( $param{'mweight'.$id} ) if $param{'mweight'.$id};
		$Paper->gsm( $param{'gsm'.$id} ) if $param{'gsm'.$id};
		if ( my $error = $Paper->save() ) {
			$variable{error} .= $error;
		} else {
			$variable{information} .= 'Paper created.<br/>';
		} # end if
	} else {
		if ( 1 < @Papers ) {
			$variable{error} .= 'Duplicate Paper Detected!.<br/>';
			$variable{information} .= 'The following papers both match, please edit them:<br/>';
			foreach my $Paper ( @Papers ) {
				$variable{information}	.= '<a href="paper_details.html?paper_id='.$Paper->id().'">'.$Paper->to_string().'</a><br/>';
			} # end foreach
		} # end if
		$Paper = shift @Papers;
		my $changed = 0;
# This is so that papers that don't have mweights will get filled in
		if ( ( ! $Paper->basis_mweight() ) and $param{'weight'.$id} ) {
			$Paper->basis_mweight( $param{'weight'.$id} * 2 );
			$changed = 1;
		} # end if
		if ( ( ! $Paper->calliper() ) and $param{'calliper'.$id} ) {
			$Paper->calliper( $param{'calliper'.$id} );
			$changed = 1;
		} # end if
		if ( ( ! $Paper->mweight() ) and $param{'txtMWeight'.$id} ) {
			$Paper->mweight( $param{'txtMWeight'.$id} );
			$changed = 1;
		} # end if
		if ( ( ! $Paper->gsm() ) and $param{'gsm'.$id} ) {
			$Paper->gsm( $param{'gsm'.$id} );
			$changed = 1;
		} # end if
		if ( ( ! $Paper->fsc_code() ) and $param{'fsc_code'.$id} ) {
			$Paper->fsc_code( $param{'fsc_code'.$id} );
			$changed = 1;
		} # end if
		foreach my $option ( 'Quality', 'Group' ) {
			
			my $option_lc = lc $option;
			if ( $param{$option} ) {
				my $option_id = $option_lc . '_id';
$log->debug("Option $option $param{$option} : " . $Paper->$option_id() );
				if ( $param{$option} != $Paper->$option_id() ) {
					$Paper->$option_id( $param{$option} );
					$changed = 1;
				} # end if
			} elsif ( $param{'txt'.$option} ) {
				$Paper->$option_lc($param{'txt'.$option});
				$changed = 1;
			} # end if
		} # end foreach option
		if ( $changed ) {
			$Paper->save();
		} # end if
	} # end if
	return $Paper;
} # end sub save_Paper

sub save_inventory {
	my ( $Skid, $Paper, $qty, $comment, $Condition, $Purpose ) = @_;
	my $delta = $Skid->add( $Paper, $qty, $Condition, $Purpose );
	$Paper->add_inventory( $Skid, $delta, $param{Units}, $comment ) if ( $delta or $comment );
#FIXME
	if ( $delta > 0 ) {
		$variable{information} .= sprintf( 'Added %1$d%2$s to inventory for skid <a href="/employee/inventory/skid_details.html?skid_id=%3$d">%3$d</a>.<br/>', $delta,$Paper->type() eq 'Roll' ? 'lbs' : 'sheets', $Skid->id() );

	} elsif ( $delta < 0 ) {
		$variable{information} .= sprintf( 'Removed %1$d%2$s from inventory for skid <a href="/employee/inventory/skid_details.html?skid_id=%3$d">%3$d</a>.<br/>', $delta,$Paper->type() eq 'Roll' ? 'lbs' : 'sheets', $Skid->id() );
	} else {
		$variable{information} .= sprintf( 'No change was made to inventory for skid <a href="/employee/inventory/skid_details.html?skid_id=%1$d">%1$d</a>.<br/>', $Skid->id() );
	}# end if

} # end sub save_inventory

sub save_Skid {
	my ( $Skid, $qty ) = @_;

	$qty = $param{Quantity} if ! defined $qty;

	my $info;
	if ( ( exists $param{rfidtag_id} ) and ( $param{rfidtag_id} ne $Skid->rfidtag_id() ) ) {
		$info .= sprintf( 'Changed rfid tag from %s to %s<br/>', $Skid->rfidtag_id(), $param{rfidtag_id} );
		$Skid->rfidtag_id( $param{rfidtag_id} );
	} # end if
	if ( ( exists $param{location_id} ) and $param{location_id} and ( $param{location_id} != $Skid->location_id() ) ) {
		$info .= sprintf( 'Changed location from %s to %s<br/>', $Skid->Location()->name(), new openprint::Location( $param{location_id} )->name() );
		$Skid->location_id( $param{location_id} );
	} # end if
	if ( ( exists $param{ddmLocation} ) and $param{ddmLocation} and ( $param{ddmLocation} != $Skid->location_id() ) ) {
		$info .= sprintf( 'Changed location from %s to %s<br/>', $Skid->Location()->name(), new openprint::Location( $param{ddmLocation} )->name() );
		$Skid->location_id( $param{ddmLocation} );
	} # end if
	if ( ( exists $param{txtLocation} ) and $param{txtLocation} and ( $param{txtLocation} != $Skid->Location()->name() ) ) {
		$info .= sprintf( 'Changed location from %s to %s<br/>', $Skid->Location()->name(), $param{txtLocation} );
		$Skid->location( $param{txtLocation} );
	} # end if
	if ( ( exists $param{manufacturers_id} ) and $param{manufacturers_id} and ( $param{manufacturers_id} != $Skid->manufacturers_id() ) ) {
		$info .= sprintf( 'Changed manufacturers id from %s to %s<br/>', $Skid->manufacturers_id(), $param{manufacturers_id} );
		$Skid->manufacturers_id( $param{manufacturers_id} );
	} # end if
	if ( exists $param{received_on_year} ) {
		if ( openprint::usergroup::is_user_in( ['InventoryManager'], $session{user_id} ) or ! $Skid->id() ) {
			if ( ! Date::Calc::check_date( @param{'received_on_year','received_on_month','received_on_day'} ) ) {
				$variable{error} .= 'Invalid Received On Date.';
			} else {
				my $date = sprintf('%.4d-%.2d-%.2d', @param{'received_on_year','received_on_month','received_on_day'});
				if ( $Skid->received_on() ne $date ) {
					$info .= sprintf( 'Changed received on date from %s to %s<br/>', $Skid->received_on(), $date );
					$Skid->received_on( $date );
				} # end if
			} # end if
		} else {
			$variable{error} .= 'You are not authorized to change the received on date.<br/>';
		} # end if
	} # end if
	if ( ! $Skid->received_on() ) {
		$info .= 'Set received on date to today<br/>';
		$Skid->received_on( join('-', Date::Calc::Today() ) );
	} # end if
	if ( $param{skid_id} and ! $Skid->id() ) {
		$info .= 'Assigning id ' . $param{skid_id} . '<br/>';	
		$Skid->id( $param{skid_id} );
	} # end if
	if ( $info and ( my $error = $Skid->save() ) ) {
		$variable{error} .= $error;
		return;
	} # end if

	my $Condition;
	if ( $param{txtCondition} ) {
		if ( ! ( $Condition = openprint::InventoryCondition->find_one('name lc'=>lc openprint::InventoryCondition->transform('name',$param{txtCondition})) ) ) {
			$Condition = new openprint::InventoryCondition();
			$variable{error} .= $Condition->save({name=>$param{txtCondition}});
		} # end if
		$param{Condition} = $Condition->id();
	} else {
		$Condition = new openprint::InventoryCondition( $param{Condition} );
	} # end if

	my $Purpose;
	if ( $param{txtPurpose} ) {
		if ( ! ( $Purpose = openprint::StockPurpose->find_one('name lc'=>lc openprint::StockPurpose->transform('name',$param{txtPurpose})) ) ) {
			$Purpose = new openprint::StockPurpose();
			$variable{error} .= $Purpose->save({name=>$param{txtPurpose}});
		} # end if
		$param{Purpose} = $Purpose->id();
	} else {
		$Purpose = new openprint::StockPurpose( $param{Purpose} );
	} # end if
	
	if ( $param{Brand} or $param{txtBrand} ) {
		my $Paper = save_Paper();

		if ( $Paper and $Paper->id() ) {
			save_inventory( $Skid, $Paper, $qty, $info, $Condition, $Purpose );

			if ( $param{Docket} ) {
				my @Projects = openprint::Project->find('docket'=>$param{Docket} );

				if ( ! @Projects ) {
					$variable{error} .= "Docket $param{Docket} not found. No paper allocated. CSR not notified.<br/>";
				} else {
					my $Project = $Projects[0] if @Projects;
					my $Allocation = openprint::PaperAllocation->find_one( 'skid_ids any'=>$$Skid{id} );
					if ( $Allocation ) {
						if ( ! sets::isin( $Allocation->project_id(), [ map { $_->id() } @Projects ] ) ) {
							$variable{error} .= sprintf('Skid is already allocated to project <a href="/employee/project/view.html?project_id=%1$d">%1$d</a>.<br/>',$Allocation->project_id() );
						} else {
							# Already allocated
						} # end if
					} else {
						$Paper->allocate( $$Skid{id}, $Project->docket(), $qty, $param{Units} );
						$variable{information} .= sprintf('Allocated %1$d%2$s to docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a>.<br/>', $qty, $param{Units}, $Project->docket() );
					} # end if
				} # end if
			} # end if
		} # end if Paper
	} elsif ( $param{Docket} ) {
		my $Order = openprint::Order->find_one( docket=>$param{Docket} );
		if ( ! $Order ) {
			$variable{error} .= "Docket $param{Docket} not found. No paper allocated.<br/>";
			return;
		} # end if

		my $Allocation = openprint::PaperAllocation->find_one( 'skid_ids any'=>$$Skid{id} );
		if ( $Allocation ) {
			if ( $Allocation->docket() != $Order->docket() ) {
				$variable{error} .= sprintf('Skid is already allocated to docket <a href="/employee/project/view.html?docket=%1$d">%1$d</a>.<br/>',$Allocation->docket() );
			} else {
# Already allocated
			} # end if
		} else {
			$Skid->allocate( undef, $Order->docket(), $qty, $param{Units} );
			$variable{information} .= sprintf('Allocated %1$d%2$s to docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a>.<br/>', $qty, $param{Units}, $Order->docket() );
		} # end if
	} # end if
} # end sub save_Skid

sub skid_details {
	if ( $param{skids} ) {
		$param{skid_id} = join(',', ref $param{skids} eq 'ARRAY' ? @{$param{skids}} : $param{skids} );
	} # end if
	$param{skid_id} =~ s/[^\d\-\,]//g;
	my @skid_ids;
	foreach my $range ( split ',', $param{skid_id} ) {
		if ( $range =~ /(\d*)\-(\d*)/ ) {
			push @skid_ids, ( $1 .. $2 );
		} else {
			push @skid_ids, $range;
		} # end if
	} # end foreach

	if ( ! @skid_ids ) {
		if ( $param{rfidtag_id} ) {
			my @RFIDTags = openprint::RFIDTag->find( 'id like' => '%'.$param{rfidtag_id}, 'order' => 'id','type'=>'Skid');
			if ( @RFIDTags == 1 ) {
				@skid_ids = ( $RFIDTags[0]->skid_id() );
				#$param{skid_id} = $skid_ids[0];
			} # end if
		} elsif ( $param{rfidtag_hex} ) {
			my @RFIDTags = openprint::RFIDTag->find( 'id like' => '%'.hex($param{rfidtag_hex}).'%', 'order' => 'id','type'=>'Skid');
			if ( @RFIDTags == 1 ) {
				@skid_ids = ( $RFIDTags[0]->skid_id() );
				#$param{skid_id} = $skid_ids[0];
			} # end if
		} # end if
	} # end if

	my $Skid = $variable{Skid} = new openprint::Skid( @skid_ids ? $skid_ids[0] : undef );
	$variable{skid_ids} = \@skid_ids;

	if ( $param{skid_id} and ! openprint::Skid->find( id=>\@skid_ids, deleted=>[0,1] ) and $param{btnFunction} ne 'Save' ) {
		$variable{error} .= "Skid $param{skid_id} not found!<br/>";
		return;
	} # end if

	$variable{similar} = 1;
	foreach ( @skid_ids ) {
		my $S = new openprint::Skid( $_ );
		if ( sets::intersection( map {$_->paper_id} ( $S->Contents(), $Skid->Contents() ) ) != scalar map { $_->paper_id } $S->Contents() ) {
			$variable{similar} = 0;
			last;
		} # end if
	} # end foreach

	if ( $param{btnFunction} ) {
		if ( $param{btnFunction} eq 'Previous' ) {
			@skid_ids = ( (new openprint::Skid( @skid_ids ? $skid_ids[0] : undef ))->previous()->id());
			$param{skid_id} = $skid_ids[0];
		} elsif ( $param{btnFunction} eq 'Next' ) {
			@skid_ids = ( (new openprint::Skid( @skid_ids ? $skid_ids[0] : undef ))->next()->id());
			$param{skid_id} = $skid_ids[0];
		} elsif ( $param{btnFunction} eq 'Save' ) {
			$session{'/employee/inventory/skid_details.html?verification_code'} = $param{verification_code} if $param{verification_code};
			my @quantities = misc::trim( split ',', $param{Quantity} );

			if ( @skid_ids and (@quantities>1) and ( @quantities != @skid_ids ) ) {
				$variable{error} .= 'When saving to multiple skids, the # of quantities must match the # of skids.You entered '.@quantities . ' but specified ' . @skid_ids . ' skids<br/>';
				return;
			} # end if
			if ( $param{rfidtag_id} ) {
				my @rfidtags = misc::trim( split ',', $param{rfidtag_id} );
				if ( @skid_ids and ( @rfidtags != @skid_ids ) ) {
					$variable{error} .= 'When saving to multiple skids, the # of rfidtags must match the # of skids.<br/>';
					return;
				} # end if

				foreach my $rfidtag_id ( @rfidtags ) {
#$log->debug( $rfidtag_id );
					if ( $_ = openprint::RFIDTag::is_invalid_id( $rfidtag_id ) ) {
						$variable{error} .= "RFIDTAG $rfidtag_id is invalid: $_.<br/>";
						next;
					} # end if
					my $RFIDTag = new openprint::RFIDTag( $rfidtag_id );
					if ( $RFIDTag->id() ) {
						my $skid_id = $RFIDTag->skid_id();
						if ( $skid_id and ( $skid_id != $param{skid_id} ) ) {
							$variable{error} .= "RFIDTAG $rfidtag_id is already assigned to skid <a href=\"/employee/inventory/skid_details.html?skid_id=$skid_id\">$skid_id</a>.<br/>";
							next;
						} # end if
					} # end if RFIDTag->id()
				} # end foreach rfidtag_id
			} # end if param{rfidtag_id}
			if ( $param{manufacturers_id} ) {
				my @manufacturers_ids = split(',', $param{manufacturers_id} );

				if ( @skid_ids ) {
					if ( @skid_ids != @manufacturers_ids ) {
						$variable{error} .= 'When saving to multiple skids, the # of manufacturer_ids must match the # of skids<br/>';
						return;
					} # en dif
					if ( my @mismatched = openprint::Skid->find( manufacturers_id => \@manufacturers_ids, 'id not in' => \@skid_ids ) ) {
						$variable{error} .= join("\n", map { sprintf('Manufacturer id %1$s is already assigned to skid <a href="/employee/inventory/skid_details.html?skid_id=%2$d">%2$d</a>.<br/>', $_->manufacturers_id(), $_->id() ) } @mismatched );
					} # end if		
				} else {

					if ( my @mismatched = openprint::Skid->find( manufacturers_id => \@manufacturers_ids ) ) {
						$variable{error} .= join("\n", map { sprintf('Manufacturer id %1$s is already assigned to skid <a href="/employee/inventory/skid_details.html?skid_id=%2$d">%2$d</a>.<br/>', $_->manufacturers_id(), $_->id() ) } @mismatched );
					} # end if		
				} # end if
			} # end if
			return if $variable{error};

# Skid_quantity only exists if adding new stock
			if ( $param{skid_quantity} ) {
				if ( @quantities != $param{skid_quantity} ) {
					$variable{error} .= 'When saving to multiple skids, the # of quantities must match the # of skids.';
					return;
				} # end if
				if ( $param{skid_quantity} > 100 ) {
					$variable{error} .= 'Cannot enter more than 100 skids/rolls at a time.';
					return;
				} # end if
				$variable{Skids} = [];
				foreach my $skid_count ( 1 .. $param{skid_quantity} ) {
					$log->debug("Entering skid $skid_count");
					my $S = new openprint::Skid();
					$param{Quantity} = @quantities > 1 ? $quantities[$skid_count-1] : $quantities[0] if @quantities;
					save_Skid( $S );
					push @{$variable{Skids}}, $S;
					if ( ! $variable{Paper} ) {
						if ( my @C = $S->Contents() ) {
							$variable{paper_id} = $C[0]->paper_id();
							$variable{Paper} = new openprint::Paper( $variable{paper_id} );
						} # end of
					} # end of
					if ( $param{verification_code} ) {
						my $SV = new openprint::Skid_Verification();
						$variable{error} .= $SV->save({
								skid_id	=>	$S->id(),
								code	=>	$param{verification_code},
								user_id	=>	$session{user_id},
								});
					} # end if verification_code
				} # end foreach
				$variable{information} .= "Added $param{skid_quantity} skids/rolls.<br/>";
			} elsif ( @skid_ids ) {
				$log->debug("sacing @skid_ids,");
				foreach my $skid_id ( @skid_ids ) {
					my $Skid = new openprint::Skid( $skid_id );
					if ( exists $param{Quantity} ) {
						$param{Quantity} = @quantities > 1 ? shift @quantities : $quantities[0] if @quantities;
						$Skid->id( $skid_id );
					} # end if
					save_Skid( $Skid );
					if ( $param{verification_code} ) {
						my $SV = new openprint::Skid_Verification();
						$SV->save({
								skid_id	=>	$skid_id,
								code	=>	$param{verification_code},
								user_id	=>	$session{user_id},
								});
					} # end if verification_code
				} # end foreach
			} else {
				$variable{error} .= 'Please enter the # of skids/rolls to enter.';
				return;
			} # end if

		} elsif ( sets::isin( $param{btnFunction}, 'Copy', 'Duplicate' ) ) {
			my @new_skid_ids;
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				$Skid = $Skid->copy();
				push @new_skid_ids, $Skid->id() if $Skid->id();
			} # end foreach
			@skid_ids = @new_skid_ids;
		} elsif ( $param{btnFunction} eq 'Delete' ) {
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				$variable{information} .= $Skid->delete();
				my $PI = new openprint::PaperInventory();
				$PI->save({skid_id=>$skid_id, user_id=>$session{user_id}, comment=>'Skid Deleted.'});
			} # end foreach
			$variable{ExternalRedirect} = '/employee/inventory/skid_details.html?skid_id='.join(',',@skid_ids);
		} elsif ( $param{btnFunction} eq 'Undelete' ) {
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				$variable{information} .= $Skid->undelete();
				my $PI = new openprint::PaperInventory();
				$PI->save({skid_id=>$skid_id, user_id=>$session{user_id}, comment=>'Skid Undeleted.'});
			} # end foreach
			$variable{ExternalRedirect} = '/employee/inventory/skid_details.html?skid_id='.join(',',@skid_ids);
		} elsif ( $param{btnFunction} eq 'Print Label' ) {
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				$Skid->print_label();
			} # end foreach
		} elsif ( $param{btnFunction} eq 'Allocate' ) {
			if ( exists $param{Captcha} ) {
# Remove spaces, because some people want to put spaces between the characters, etc.
				$param{Captcha} =~ s/\s//g;
				my $Captcha = new Authen::Captcha(
						data_folder => $config{SkinPath}.'/tmp',
						output_folder => $config{SkinPath}.'/images/captcha'
						);
				if ( 1 != $Captcha->check_code( @param{'Captcha','MD5SUM'} ) ) {
					$variable{error} .= 'Captcha Validation Code incorrect.	Please try again.';
					return;
				} # end if
			} # end if
			foreach my $skid_id ( @skid_ids ) {
				foreach my $condition_id ( sets::union( map { $_->condition_id() } openprint::SkidContent->find(skid_id=>$skid_id, paper_id=>$param{paper_id},'quantity >' =>0 ) ) ) {
					next if ! $param{'quantity-'.$condition_id};
					allocate( $skid_id, @param{'paper_id','quantity-'.$condition_id,'Project','Docket','specific','reason'}, $condition_id );
				} # end foreach condition
			} # end foreach
		} elsif ( $param{btnFunction} eq 'Delete Allocation' ) {
			if ( $param{allocation_id} ) {
				my $PA = new openprint::PaperAllocation( $param{allocation_id} );
				$PA->delete();
			} # end if
		} elsif ( $param{btnFunction} eq 'CheckIn' ) {
			foreach my $skid_id ( @skid_ids ) {
				check_in( $skid_id, @param{'paper_id', 'Quantity','Project','Docket','reason'} );
			} # end foreach
			$variable{ExternalRedirect} = '/employee/inventory/skid_details.html?skid_id='.join(',',@skid_ids);
		} elsif ( $param{btnFunction} eq 'CheckOut' ) {
			my $qty = $param{Quantity};
			foreach my $skid_id ( @skid_ids ) {
				$qty -= check_out( $skid_id, $param{paper_id}, $qty, @param{'Project','Docket','reason'} );
				last if ! $qty;
			} # end foreach
			$variable{ExternalRedirect} = '/employee/inventory/skid_details.html?skid_id='.join(',',@skid_ids);
		} elsif ( $param{btnFunction} eq 'DeletePaper' ) {
			my $C = new openprint::SkidContent($param{content_id});
			if ( ! $C->id() ) {
				$variable{error} .= 'Paper not found on skid. No changes made.<br/>';
				$log->error("Paper not found on skid. WHy?!");
			} else {
				my $PI = new openprint::PaperInventory();
				$PI->save({ user_id=>$session{user_id}, skid_id=>$C->Skid()->id(), paper_id=>$$C{paper_id}, comment=>'Deleted from skid.'});
				$variable{error} .= $C->delete();
				$variable{ExternalRedirect} = '/employee/inventory/skid_details.html?skid_id=>'.$$C{skid_id};
			} # end if
		} # end if whih btnFunction
	} # end if btnFunction

	$variable{Skid} = new openprint::Skid( @skid_ids ? $skid_ids[0] : undef );
	$variable{skid_id} = $variable{Skid}->id() ? $variable{Skid}->id() : $param{skid_id};
	$variable{skid_ids} = \@skid_ids;

} # end sub skid_details

sub check_out {
	my ( $skid_id, $paper_id, $quantity, $project_id, $docket, $reason ) = @_;

	if ( ! ( $paper_id or $skid_id ) ) {
		$variable{error} .= 'Skid or Paper not specified. No paper checked out.<br/>';
		return;
	} # end if
	my $Paper;
	if ( $paper_id ) {
		$Paper = new openprint::Paper( $paper_id );
	} elsif ( $skid_id ) {
		my $Skid = new openprint::Skid( $skid_id );
		my @papers = $Skid->Contents();
		if ( 1 == @papers ) {
			$Paper = $papers[0]->Paper();
			$paper_id = $Paper->id();
		} else {
			$variable{error} .= 'Skid contains more than one type of paper.	You must specify.<br/>';
			return;
		} # end if
	} # end if

	my $available_qty = $Paper->in_stock();
	my $units = $Paper->type() eq 'Roll' ? 'lbs' : 'sheets';
	$project_id = openprint::Project->transform( 'id', $project_id );
	$docket = openprint::Project->transform( 'docket', $docket );
	my @Projects = openprint::Project->find( 
		( $project_id ? ( id=>$project_id ) : () ),
		( $docket ? ( docket=>$docket ) : () ),
	) if $project_id or $docket;

	my @skids;
	if ( $skid_id ) {
		@skids = ( $skid_id );
	} else {
		@skids = sql::execute( undef, undef, q{SELECT skid_id FROM skid_contents WHERE paper_id=? ORDER BY skid_id}, $paper_id );
	} # end if
	if ( ! @skids ) {
		$variable{error} .= 'There are no skids for this paper. Cannot check out.<br/>';
		return;
	} # end if

	my $description =	'Checked out';
	if ( @Projects ) {
		$description .= sprintf( ' for docket <a href="/employee/project/view.html?docket=%1$d">%1$d</a>', $Projects[0]->docket() );
	} # end if
	if ( $reason ) {
		$description .= ': ' . $reason;
	} # end if

	my $qty = $quantity;
	foreach my $skid_id ( @skids ) {
		my $Skid = new openprint::Skid( $skid_id );
		my $C = $Skid->Content( $Paper );
		if ( $C->quantity() <= 0 ) {
			# No paper on skid
		} elsif ( $C->quantity() < $qty ) {
			my $amount = $C->quantity();
			$qty -= $amount;
			$amount *= -1;
			$C->save({'quantity'=>0});
			$Paper->add_inventory( $Skid, $amount, $units, $description, @Projects ? $Projects[0] : () );
			$Paper->allocate( $Skid->id(), $Projects[0]->docket(), $amount ) if @Projects and $Paper->allocated( $Projects[0]->docket() );
		} else {
			$C->save({ quantity=>($C->quantity() - $qty)});
			if ( @Projects ) {
				$Paper->add_inventory( $Skid, -1*$qty, $units, $description, $Projects[0] );
				$Paper->allocate( $Skid->id(), $Projects[0]->docket(), -1*$qty ) if $Paper->allocated( $Projects[0]->docket() );
			} else {
				$Paper->add_inventory( $Skid, -1*$qty, $units, $description );
			} # end if
			$qty = 0;
		} # end if
		delete $$Skid{Contents};
		last if ! $qty;
	} # end foreach

	if ( @Projects ) {
		$variable{information} .= sprintf('Checked out %1$d%2$s to docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a><br/>', $quantity, $units, $Projects[0]->docket() );
	} else {
		$variable{information} .= "Checked out $quantity$units to unknown docket.<br/>";
	} # end if
	return $quantity;
} # end sub check_out

sub check_in {
	my ( $skid_id, $paper_id, $quantity, $project_id, $docket, $reason, $Condition ) = @_;
	if ( ! ( $paper_id or $skid_id ) ) {
		$variable{error} .= 'Skid or Paper not specified. No paper checked in.<br/>';
		return;
	} # end if
	my $Paper;
	my $Skid = new openprint::Skid( $skid_id );

	if ( $paper_id ) {
		$Paper = new openprint::Paper( $paper_id );
	} elsif ( $skid_id ) {
		my @papers = $Skid->Contents();
		if ( 1 == @papers ) {
			$Paper = $papers[0]->Paper();
			$paper_id = $Paper->id();
		} else {
			$variable{error} .= 'Skid contains more than one type of paper. You must specify.<br/>';
			return;
		} # end if
	} # end if
	if ( ! $Condition ) {
		my $C = $Skid->Content( $Paper );
		$Condition = $C->Condition();
	} elsif ( DEBUG ) {
		$log->debug("check_in: Condition is $Condition");
	} # end if
	$project_id =~ s/\D//g;
	$docket =~ s/\D//g;
	my @Projects = openprint::Project->find( 
		( $project_id ? ( id=>$project_id ) : () ),
		( $docket ? ( docket=>$docket ) : () ) 
		) if $project_id or $docket;

# Default to add
	$quantity =~ s/[^\d\.\-]//g;
$log->debug("Checking in $quantity");
	if	( $quantity =~ /^\d/ ) {
		$quantity = '+' . $quantity;
	} # end if

	my $description = 'Added';
	if ( @Projects ) {
		$description .= sprintf(' from docket <a href="/employee/project/view.html?ProjectIndex=%d">%d</a>', $Projects[0]->id(), $Projects[0]->docket() );
	} # end if
	if ( $reason ) {
		$description .= ' : ' . $reason;
	} # end if

	my $units = $Paper->units();
	my $delta = $Skid->add( $Paper, $quantity, $Condition );
	if ( ! @Projects ) {
		$Paper->add_inventory( $Skid, $delta, $units, $description );
		$variable{information} .= "Checked in $quantity$units from unknown docket.<br/>";
	} else {
		my $Project = shift @Projects;
		$Paper->add_inventory( $Skid, $delta, $units, $description, $Project );
		$variable{information} .= sprintf('Checked in %1$d%2$s from docket <a href="/employee/project/view.html?ProjectIndex=%3$d">%4$d</a><br/>', $quantity, $units, $Project->id(), $Project->docket() );
	} # end if
	$Skid->save();
} # end sub check_in

# allocate
# skid_ids is plural because it may be a comma delimited string of skid_ids
sub allocate {
	my ( $skid_ids, $paper_id, $quantity, $project_id, $docket, $specific, $reason, $condition_id ) = @_;
	if ( ! $paper_id ) {
		$variable{error} .= 'Paper not specified. No paper allocated.<br/>';
		return;
	} # end if
	my $Paper = new openprint::Paper( $paper_id );
	if ( ! $Paper->id() ) {
		$variable{error} .= 'Invalid stock specified. No stock allocated.<br/>';
		return;
	} # end if
	my $units = $Paper->units();
	$docket =~ s/\D//g;
	$quantity =~ s/[^\-\d]//g; # Inputs are all integers, not floats

	my $Order = openprint::Order->find_one( docket=>$docket ) if $docket;
	if ( ( ! $Order ) and $project_id ) {
		my $Project = new openprint::Project( $project_id );
		$Order = $Project->Order() if $Project;
	} # end if

	if ( ! $Order ) {
		$variable{error} .= 'An invalid Docket or Project # was given. No paper allocated.<br/>';
		return;
	} # end if

	my @skid_ids = split(',', $skid_ids );
	if ( ! @skid_ids ) {
		if ( $quantity < 0 ) {
			@skid_ids = map { $_->skid_ids() ? @{$_->skid_ids()} : () } openprint::PaperAllocation->find(paper_id=>$paper_id, docket=>$Order->docket(), ( $condition_id ? ( condition_id=>$condition_id ) : () ) );
$log->debug("Got sids from allocations to deallocate: @skid_ids");
		} elsif ( $specific ) {
			@skid_ids = map { $_->skid_id() } openprint::SkidContent->find( deleted=>0, paper_id=>$paper_id, ( $condition_id ? ( condition_id=>$condition_id ) : () ) );
		} # end if
	} # end if

	my $qty = $quantity;
	my @allocated_skids;

	if ( $qty < 0 ) {
		# De-allocation
		# if specific, look for allocations to delte
		$qty *= -1;
		
		my @PAs;
		if ( $specific ) {
			# Prefer specific allocations first.
			@PAs = openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids is null' => 0,
				( $condition_id ? ( condition_id=>$condition_id ) : () ),
				order	=>	'id DESC'
			);
			@PAs = openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids is null' => 0,
				order	=>	'id DESC'
			) if ! @PAs;
			push @PAs, openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids is null' => 1,
				( $condition_id ? ( condition_id=>$condition_id ) : () ),
				order	=>	'id DESC'
			);
			push @PAs, openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids is null' => 1,
				order	=>	'id DESC'
			) if ! @PAs;
		} else {
			@PAs = openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids' => '{}',
				( $condition_id ? ( condition_id=>$condition_id ) : () ),
				order	=>	'id DESC'
			);
			@PAs = openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids' => '{}',
				order	=>	'id DESC'
			) if ! @PAs;
			push @PAs, openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids !=' => [],
				( $condition_id ? ( condition_id=>$condition_id ) : () ),
				order	=>	'id DESC'
			);
			push @PAs, openprint::PaperAllocation->find( paper_id=>$paper_id, docket=>$Order->docket(),
				'skid_ids !=' => [],
				order	=>	'id DESC'
			) if ! @PAs;
		} # end if
		while ( $qty > 0 and my $PA = shift @PAs ) {
			if ( $PA->quantity() > $qty ) {
				$PA->save({quantity=>$PA->quantity() - $qty });
				$qty = 0;
			} else {
				$qty -= $PA->quantity();
				$PA->delete();
			} # end if
		} # end while
	
		
		if ( $qty == -1*$quantity ) {
			$variable{error} .= 'Failed to deallocate.';
		} else {
			$variable{information} .= sprintf('Deallocated %1$d%2$s from docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a><br/>', 
				Number::Format::format_number($qty ? $qty : -1*$quantity), $units, $Order->docket() );
			$Order->add_log( 'De-Allocated ' . Number::Format::format_number($qty ? $qty : -1*$quantity).$$Paper{units}.qq` of <a href="/employee/inventory/paper_details.html?paper_id=$paper_id">` . $Paper->to_string().'</a>');
			my $PI = new openprint::PaperInventory();
			$PI->save({	
				paper_id	=>	$paper_id,
				user_id		=>	$session{user_id},
				docket		=>	$Order->docket(),
				delta		=>	0,
				comment		=>	$variable{information},
				instock		=>	$Paper->in_stock(),
			});
		} # end if
	} else {
					
		if ( @skid_ids ) {
	
			# I don't understand the point of this.
			#foreach my $skid_id ( @skid_ids ) {
				#my $Skid = new openprint::Skid( $skid_id );
				#my $allocateable = $Skid->allocateable( $Paper );
				#next if ! $allocateable;
#
				#
				#if ( $allocateable < -1*$qty ) {
					#push @allocated_skids, $skid_id;
					##push @allocations, $Paper->allocate( $skid_id, $Projects[0]->id(), -1*$allocateable, $units );
					#$qty += $allocateable;
				#} else {
					#push @allocated_skids, $skid_id;
					##push @allocations, $Paper->allocate( $skid_id, $Projects[0]->id(), $qty, $units );
					#$qty = 0;
				#} # end if
				#last if ! $qty;
			#} # end foreach
		#} else {
			foreach my $skid_id ( @skid_ids ) {
				my $Skid = new openprint::Skid( $skid_id );
				my $allocateable = $Skid->allocateable( $Paper );
				next if ! $allocateable;
				push @allocated_skids, $skid_id;
				$qty -= $allocateable;
				last if $qty <= 0;
			} # end foreach
			if ( $qty > 0 ) {
				$variable{warning} .= 'There is not enough available paper to allocate.';
			} # end if
		} else {
			my @SkidContents = openprint::SkidContent->find(
					condition_id	=>	$condition_id,
					paper_id		=>	$paper_id,
					'quantity >'	=>	1,
					deleted			=>	0,
					);
			next if ! @SkidContents;
			my @Allocations = openprint::PaperAllocation->find(
					condition_id	=>	$condition_id,
					paper_id		=>	$paper_id,
					);

			my $available = misc::sum(map { $_->quantity() } @SkidContents) - misc::sum(map { $_->quantity() } @Allocations );
			if ( $available < $qty ) {
				$variable{warning} .= 'There is not enough available paper to allocate.';
			} # end if
		} # end if
		my $PA = $Paper->allocate( \@allocated_skids, $Order->docket(), $quantity, $units, $condition_id );
		
		$PA->send_notification();
		$variable{information} .= sprintf('Allocated %s%s to docket <a href="/employee/project/view.html?docket=%3$d">%3$d</a><br/>', 
			Number::Format::format_number($quantity), $units, $Order->docket() );
	} # end if allocate or deallocate
} # end sub allocate


sub send_paper_arrival_notification {
	my ( $Skid, @papers ) = @_;
	my %info;
	$info{Skid} = $Skid;

	@papers = map { new openprint::Paper( $_ ) } keys %{$Skid->paper()} if ! @papers;
	require MIME::QuotedPrint;

	foreach my $Paper ( @papers ) {
		$info{Paper} = $Paper;
		my $C = $Skid->Content( $Paper );
		$info{Quantity} = $C ? $C->quantity() : 0;
		
		my @To = map { new openprint::User( $_ ); } sets::union( map { $_->Project->Order()->salesrep_id() } openprint::PaperAllocation->find('skid_ids any'=>$Skid->id(),paper_id=>$Paper->id()) );

		if ( @To ) {
# Send notification to maybe CSR's
			my $email_template = ssi::slurp_content( '/email_template.html' );

			$info{ReplacementText} = ssi::include( '/email_content/paper_arrived_notification.html', \%info );
			(new openprint::Email())->send(
					FROM	=> new openprint::User( $session{user_id} ),
					TO	=> @To,
					SUBJECT => 'Paper ' . $Paper->to_string() . ' has arrived',
					ATTACHMENTS=>['', MIME::QuotedPrint::encode_qp( ssi::variable_substitution( \$email_template, \%info ) ), 'text/html', 'quoted-printable'],
					);
		} # end if to
	} # end foreach Paper
} # end sub send_paper_arrival_notification

sub rfidtags {
	if ( $param{btnFunction} eq 'Delete' ) {
		foreach my $rfidtag_id ( ref $param{rfidtags} eq 'ARRAY' ? @{$param{rfidtags}} : split(',',$param{rfidtags}) ) {
			my $RFIDTag = new openprint::RFIDTag( $rfidtag_id );
			$variable{error} .= $RFIDTag->delete();
		} # end foreach rfidtag_id
	} elsif ( $param{btnFunction} eq 'Validate' ) {
		foreach my $rfidtag_id ( ref $param{rfidtags} eq 'ARRAY' ? @{$param{rfidtags}} : split(',',$param{rfidtags}) ) {
			my $RFIDTag = new openprint::RFIDTag( $rfidtag_id );
			$variable{error} .= $RFIDTag->save({'valid'=>1});
		} # end foreach rfidtag_id
	} else {
		ssi::save_params( '/employee/inventory/rfidtags.html', 'Type', 'created_on_start_year','created_on_start_month','created_on_start_day','created_on_end_year','created_on_end_month','created_on_end_day','updated_on_start_year','updated_on_start_month','updated_on_start_day','updated_on_end_year','updated_on_end_month','updated_on_end_day', 'assigned', 'notassigned','valid', 'location_id' );
		ssi::setup_date_select( '/employee/inventory/rfidtags.html', 'created_on_start', 0 );
		ssi::setup_date_select( '/employee/inventory/rfidtags.html', 'created_on_end', '' );
		ssi::setup_date_select( '/employee/inventory/rfidtags.html', 'updated_on_start', '' );
		ssi::setup_date_select( '/employee/inventory/rfidtags.html', 'updated_on_end', '' );
		if ( ! exists $session{'/employee/inventory/rfidtags.html?assigned'} ) {
			$session{'/employee/inventory/rfidtags.html?assigned'} = 1;
		} # end if
		if ( ! exists $session{'/employee/inventory/rfidtags.html?notassigned'} ) {
			$session{'/employee/inventory/rfidtags.html?notassigned'} = 1;
		} # end if
	} # end if
} # end sub rfidtags

sub _rfidtags_results {
	ssi::save_params( '/employee/inventory/rfidtags.html', 'Type', 'created_on_start_year','created_on_start_month','created_on_start_day','created_on_end_year','created_on_end_month','created_on_end_day','updated_on_start_year','updated_on_start_month','updated_on_start_day','updated_on_end_year','updated_on_end_month','updated_on_end_day', 'assigned', 'notassigned','valid','location_id' );
} # end sub _rfidtags_results

sub rfidtag_details {
		if ( $param{rfidtag_id} =~ /^\s*\((.*)\)\s*$/ ) {
			$param{rfidtag_id} = hex( $1 );
		} else {
			$param{rfidtag_id} = openprint::RFIDTag->transform( id=>$param{rfidtag_id} );
		} # end if

		if ( $param{rfidtag_id} ) {
			my $rfid = $param{rfidtag_id};
			$rfid = sprintf('2%.14d', $rfid );
			my $RFIDTag = openprint::RFIDTag::from_id( $rfid );
			if ( $RFIDTag ) {
				$param{rfidtag_id} = $RFIDTag->id();
			} else {
				my @Tags = openprint::RFIDTag->find('id like'=>( $param{rfidtag_id} =~ /%/ ? $param{rfidtag_id} : '%'.$param{rfidtag_id} ) );
				if ( ! @Tags ) {
					$variable{error} .= 'Tag ID not found.';
				} elsif ( @Tags > 1 ) {
					@{$variable{Tags}} = @Tags;
				} else {
					$param{rfidtag_id} = $Tags[0]->id();
				} # end if
			}
		} else {
			$variable{error} .= 'Please specify an id (or part).<br/>';
		} # end if
		
	my $RFIDTag = new openprint::RFIDTag( $param{rfidtag_id} );
	$RFIDTag->id( $param{rfidtag_id} ) if ! $RFIDTag->id();
	
	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $RFIDTag->save( \%param );
		$variable{ExternalRedirect} = '/employee/inventory/rfidtag_details.html?rfidtag_id='.$RFIDTag->id();
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $RFIDTag->delete();
	} elsif ( $param{btnFunction} eq 'AllocateSkid' ) {
		if ( ! $RFIDTag->skid_id() ) {
			my $Skid = new openprint::Skid();
			$Skid->rfidtag_id( $RFIDTag->id() );
			$Skid->location_id( $RFIDTag->location_id() );
			$variable{error} .= $Skid->save();
		} else {
			$variable{error} .= 'Skid already allocated<br/>';
		} # end if
	} # end if

	_rfidtag_log_entries();

	$variable{RFIDTag} = $RFIDTag;
} # end sub rfidtag_details

sub rfidscanners {
	if ( $param{btnFunction} eq 'Delete' ) {
		if ( $param{rfidscanners} ) {
			foreach my $id ( ref $param{rfidscanners} eq 'ARRAY' ? @{$param{rfidscanners}} : split(',',$param{rfidscanners}) ) {
				$variable{error} .= new openprint::RFIDScanner( $id )->delete();
			} # end foreach
		} elsif ( $param{rfidscanner_id} ) {
			my $RFIDScanner = new openprint::RFIDScanner( $param{rfidscanner_id} );
			$variable{error} .= $RFIDScanner->delete();
		} # end if
	} # end if
	_rfidscanners();
} # end sub rfidscanners
sub _rfidscanners {
	ssi::save_params( '/employee/inventory/rfidscanners.html', ( 'Type','created_on_start_year','created_on_start_month','created_on_start_day','created_on_end_year','created_on_end_month','created_on_end_day','assigned','notassigned','updated_on_start_year','updated_on_start_month','updated_on_start_day','updated_on_end_year','updated_on_end_month','updated_on_end_day' ) );
} # end sub _rfidscanners

sub rfidscanner_details {
	my $RFIDScanner = new openprint::RFIDScanner( $param{rfidscanner_id} );
	
	if ( $param{btnFunction} eq 'Previous' ) {
		$RFIDScanner = $RFIDScanner->Previous();
		$param{rfidscanner_id} = $RFIDScanner->id();
	} elsif ( $param{btnFunction} eq 'Next' ) {
		$RFIDScanner = $RFIDScanner->Next();
		$param{rfidscanner_id} = $RFIDScanner->id();
	} # end if

	if ( $param{btnFunction} eq 'Save' ) {
		$variable{error} .= $RFIDScanner->save( \%param );
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $RFIDScanner->delete();
	} else {
		@param{'StartYear','StartMonth','StartDay'} = Date::Calc::Today();
		@param{'EndYear','EndMonth','EndDay'} = Date::Calc::Today();
		_rfidscanner_log();
	} # end if

	$variable{RFIDScanner} = $RFIDScanner;
} # end sub rfidscanner_details

sub _rfidscanner_log { 
	my $url = '';

	$variable{Entries} = [ openprint::RFIDScannerHistory->find( 
			scanner_id		=>	$param{rfidscanner_id},
			ssi::date_filter( $url.'location_log_start', 'updated_on_start', \%param ),
			ssi::date_filter( $url.'location_log_end', 'updated_on_end', \%param ),
			( $param{limit} ? ( $param{limit} eq 'All' ? () : ( limit	 =>	$param{limit} ) ) : ( limit=>10 ) ),
			order	 =>	'updated_on DESC',
			) ];
} # end sub rfid_scanner_log

sub save_Manifest {
	my ( $Manifest ) = @_;

	my $error;
	
	$param{received_on} = join('-', @param{'received_on_year','received_on_month','received_on_day'});

	my $ac = sql::start_transaction( $dbh );
	$dbh->do( 'LOCK TABLE companies IN SHARE ROW EXCLUSIVE MODE' ) or $log->error( DBI->errstr );

	if ( $param{supplier} and ! $param{supplier_id} ) {
		my @Companies = openprint::Company->find( name=>$param{supplier} );
		if ( ! @Companies ) {
			my $C = new openprint::Company();
			$error .= $C->save({
					supplier		=> 'Y',
					name			=> $param{supplier},
					business_name	=> $param{supplier},
					} );
			$param{supplier_id} = $C->id();
		} elsif ( @Companies == 1 ) {
			if ( $Companies[0]->supplier() ne 'Y' ) {
				$error .= $Companies[0]->save( { supplier=>'Y' } );
			} # end if
			$param{supplier_id} = $Companies[0]->id();
		} # end if
	} elsif ( ! ( $param{supplier} and $param{supplier_id} ) ) {
# No vendor supplied, look in POs.
			my @Types = openprint::Manifest_Content_Type->find(manifest_id=>$Manifest->id());
			my @vendor_ids = sets::union( map { $param{"po_id-$$_{id}"} ? new openprint::PurchaseOrder($param{"po_id-$$_{id}"})->supplier_id(): () } @Types );
			if ( @vendor_ids == 1 ) {
			$param{supplier_id} = $vendor_ids[0];
			}
	} # end if supplier and ! supplier_id
	sql::end_transaction( $dbh, $ac );

	$ac = sql::start_transaction( $dbh );
	$dbh->do( 'LOCK TABLE Manifests IN EXCLUSIVE MODE' ) or $log->error( DBI->errstr );

	my $Log = new openprint::Log();
	$Log->set({Object=>$Manifest, action=>'Save Manifest'});

	my @changes = $Manifest->changes(\%param);
	if ( @changes ) {
		$error .= $Manifest->save( \%param );
		$Log->save({ note=>'Changes: ' . join('=>', @changes) });
	}

	my @Types = openprint::Manifest_Content_Type->find(manifest_id=>$Manifest->id());
	if ( ! @Types ) {
		# It's an empty, brand new manifest
		my $Type = new openprint::Manifest_Content_Type();
		$error .= $Type->save({ manifest_id=>$Manifest->id() });
		sql::end_transaction( $dbh, $ac );
		return $error;
	} # end if

	foreach my $Type ( @Types ) {
		my $Paper = save_Paper('-'.$Type->id());
		
		my %data = (
			docket		=>	$param{'docket-'.$Type->id()},
			paper_id	=>	$Paper->id(),
			( ( ! $$Type{type} ) ? ( type		=>	$Paper->type() ) : () ),
			po_id		=>	$param{'po_id-'.$Type->id()},
			manufacturers_name	=>	$param{'manufacturers_name-'.$$Type{id}},
			item_count	=>	$param{'item_count-'.$$Type{id}},
			condition_id	=>	$param{'condition_id-'.$$Type{id}},
		);
		$data{cost} = $param{'cost-'.$Type->id()} if exists $param{'cost-'.$Type->id()};
		$data{supplier_invoice} = $param{'supplier_invoice-'.$Type->id()} if exists $param{'supplier_invoice-'.$Type->id()};

		@changes = $Type->changes(\%data);
		if ( @changes ) {
			$Log->save({ note=>$$Log{note} . '<br/>Type: ' . join('=>', @changes) });
			$variable{error} .= $Type->save(\%data) if @changes;
		}

		my $NewMC = new openprint::ManifestContent();
		$NewMC->set({manifest_id=>$$Manifest{id}, type_id=>$$Type{id}});

		my $total_qty = 0;
		# Save data for the rest of the contents
		foreach my $MC ( $NewMC, $Manifest->Contents( type_id => $$Type{id} ) ) {
			my $changed = 0;

			$param{"skid_id-$$Type{id}-$$MC{id}"} = openprint::Skid->transform( 'id', $param{"skid_id-$$Type{id}-$$MC{id}"} );

			if ( $param{"skid_id-$$Type{id}-$$MC{id}"} != $$MC{skid_id} ) {
				$MC->skid_id( $param{"skid_id-$$Type{id}-$$MC{id}"} );
				$changed = 1;
			} # end if

			if ( exists $param{"rfidtag_id-$$Type{id}-$$MC{id}"} ) {
				$param{"rfidtag_id-$$Type{id}-$$MC{id}"} = openprint::RFIDTag->transform( 'id', $param{"rfidtag_id-$$Type{id}-$$MC{id}"} );
				$MC->rfidtag_id( $param{"rfidtag_id-$$Type{id}-$$MC{id}"} );
				$changed = 1;
			} # end if
			my $Tag = $MC->RFIDTag();
			if ( $param{"manufacturers_id-$$Type{id}-$$MC{id}"} ne $$MC{manufacturers_id} ) {
				$$MC{manufacturers_id} = $param{"manufacturers_id-$$Type{id}-$$MC{id}"};
				$changed = 1;
			} # end if

			my $Skid = $MC->Skid();
$log->debug("Skid: " . $Skid->to_string() );
			if ( $$MC{manufacturers_id} ) {
				my $found_other_skid = 0;
				if ( my $S = openprint::Skid->find_one(manufacturers_id=>$$MC{manufacturers_id}) ) {
$log->debug("manufact Skid: " . $S->to_string() );
					if ( $Skid->id() ) {
						if ( $S->id() != $Skid->id() ) {
							$error .= "Manufacturers ID $$MC{manufacturers_id} for skid <a href=\"/employee/inventory/skid_details.html?skid_id=$$MC{skid_id}\">$$MC{skid_id}</a> is already assigned to <a href=\"/employee/inventory/skid_details.html?skid_id=$$S{id}\">$$S{id}</a>.";
							$error .= ssi::button( 'Replace'.$$MC{id}, { href=>'/employee/inventory/manifest.html?manifest_content_id='.$$MC{id}.'&action=replace&skid_id='.$$S{id}, text=>'Replace' } ) . '<br/>';
							$found_other_skid = 1;
						} # end if
					} else {
						$Skid = $S;
					} # end if
				} # end if
			} # end if manufacturers_id
				
			if ( ( ! $$MC{skid_id} ) and $Skid->id() ) {
				$MC->skid_id( $$Skid{id} );
				$changed = 1;
			} # end if

			my $qty_param = $Type->type() eq 'Sheet' ? "qty_sheets-$$Type{id}-$$MC{id}" : "qty_lbs-$$Type{id}-$$MC{id}";
$log->debug("param: $qty_param $param{$qty_param}");
			if ( exists $param{$qty_param} and ( $MC->quantity() != $param{$qty_param} ) ) {
$log->debug("param: $qty_param $param{$qty_param} $$MC{quantity}");
				$MC->quantity( Math::Round::nearest(1, $param{$qty_param}) );
				$changed = 1;
			} # end if

			if ( ! ( $$MC{id} or $$MC{skid_id} or $$MC{rfidtag_id} or $$MC{quantity} ) ) {
				next;
			} # end if
$log->debug( " location: " . $param{"location_id-$$Type{id}-$$MC{id}"} . ' != ' . $MC->location_id() );
			if ( $param{"location_id-$$Type{id}-$$MC{id}"} != $MC->location_id() ) {
$log->debug( "Updaating location: " . $param{"location_id-$$Type{id}-$$MC{id}"} . ' != ' . $MC->location_id() );
				$$MC{location_id} = $param{"location_id-$$Type{id}-$$MC{id}"};
				$changed = 1;
			} # end if changed location_id
			$error .= $MC->save() if $changed;
			$total_qty += $MC->quantity();
		} # end foreach Manifest_Content for this type

if ( 0 ) {
		if ( $param{'po_id-'.$Type->id()} ) {
			my $PO = new openprint::PurchaseOrder( $param{'po_id-'.$Type->id()} );
			if ( $PO->id() ) {
				$variable{error} .= $PO->save({manifest_id=>$Manifest->id()}) if $PO->manifest_id() != $Manifest->id();;

				# Run through, and warn if the PO is not satisfied
				my $PO_Content = $Type->PurchaseOrder_Content();
				if ( $PO_Content->qty() > $total_qty ) {
					$variable{warning} .= 'There is not enough stock to satisfy PO ' . $PO->id().'<br/>
						Manifest has ' . $total_qty . $Type->Paper()->units() . ' of '. $Paper->to_string()	.'<br/>
						PO wants ' . $PO_Content->qty() . $PO_Content->units() . ' of ' . $PO_Content->item().'<br/>';
				} # end if	
			} else {
				$variable{error} .= 'Purchase Order ' . $param{'po_id-'.$Type->id()} . ' was not found in the system.<br/>';
			} # end if
		} # end if po_id
} 

	} # end foreach Type
	sql::end_transaction( $dbh, $ac );
	return $error;
} # end sub save_Manifest

sub apply_Manifest {

	my ( $Manifest ) = @_;

	my $error;

	my $Log = new openprint::Log();
	$Log->save({
			object_type => 'openprint::Manifest',
			object_id=>$$Manifest{id},
			action=>'Apply Manifest',
			user_id=>$session{user_id},
			company_id=>$session{company_id}
			});
	my $ac = sql::start_transaction( $dbh );
	$dbh->do( 'LOCK TABLE Manifests IN EXCLUSIVE MODE' ) or $log->error( DBI->errstr );

	foreach my $Type ( openprint::Manifest_Content_Type->find( manifest_id=>$Manifest->id()) ) {
		my $Paper = $Type->Paper();
		my $Order = $Type->Order();
			
		# If there is a change of paper in the type, then go through each skid and update them, nicluding allocations, and add a log entry so we know that it happened.
		if ( $Type->manufacturers_name() and $Type->paper_id() and ! $Paper->manufacturers_name() ) {
			$error .= $Paper->save({manufacturers_name=>$Type->manufacturers_name()});
		} # end if

		my $total_qty = 0;
# Save data for the rest of the contents
		foreach my $MC ( $Manifest->Contents( type_id => $$Type{id} ) ) {
			$error .= $MC->apply( $Order );

			$total_qty += $MC->quantity();
		} # end foreach Manifest_Content for this type

		if ( $param{'po_id-'.$Type->id()} ) {
			my $PO = openprint::PurchaseOrder->find_one( id=>$param{'po_id-'.$Type->id()} );
			if ( $PO ) {
				$error .= $PO->save({manifest_id=>$Manifest->id()}) if $PO->manifest_id() != $Manifest->id();;

# Run through, and warn if the PO is not satisfied
				my $PO_Content = $Type->PurchaseOrder_Content();
				if ( $PO_Content ) {
					if ( $PO_Content->qty() > $total_qty ) {
						$variable{warning} .= 'There is not enough stock to satisfy PO ' . $PO->id().'<br/>
							Manifest has ' . $total_qty . $Type->Paper()->units() . ' of '. $Paper->to_string()	.'<br/>
							PO wants ' . $PO_Content->qty() . $PO_Content->units() . ' of ' . $PO_Content->item().'<br/>';
					} # end if	
				} else {
					$error .= 'No matching line found in Purchase Order ' . $param{'po_id-'.$Type->id()} . '.<br/>';
				} # end if POC
			} else {
				$error .= 'Purchase Order ' . $param{'po_id-'.$Type->id()} . ' was not found in the system.<br/>';
			} # end if
		} # end if po_id

		# Update in_stock
		$error .= $Paper->save();
	} # end foreach Type
	sql::end_transaction( $dbh, $ac );
	return $error;
} # end sub apply_Manifest

sub manifest {
	$param{manifest_id} =~ s/\s//g;
	my $Manifest = new openprint::Manifest( $param{manifest_id} );
	if ( $param{action} eq 'import' ) {
		manifest_import();
		return;
	} elsif ( $param{action} eq 'replace' ) {
		my $MC = new openprint::ManifestContent( $param{manifest_content_id} );
		
		if ( ! $$MC{id} ) {
			$variable{error} .= 'Manifest Content not found.  No change made.';
		} elsif ( $$MC{skid_id} == $param{skid_id} ) {
			$variable{error} .= 'Skid already replaced. No change made.';
		} else {
			my $Skid_to_delete = $MC->Skid();
			$variable{error} .= $MC->save({skid_id=>$param{skid_id}});
			$variable{error} .= $Skid_to_delete->delete();
			$variable{ExternalRedirect} = '/employee/inventory/manifest.html?manifest_id='.$$MC{manifest_id};
		} # end if
		$Manifest = $MC->Manifest();
	
	} elsif ( $param{btnFunction} eq 'Delete' ) {
		$variable{error} .= $Manifest->delete();
		if ( ! $variable{error} ) {
			$variable{Redirect} = '/employee/inventory/manifests.html';
			%param = ();
		} # end if
	} elsif ( $param{btnFunction} eq 'undelete' ) {
		$variable{error} .= $Manifest->undelete();
		if ( ! $variable{error} ) {
			$variable{Redirect} = '/employee/inventory/manifests.html';
			%param = ();
		} # end if
	} elsif ( $param{btnFunction} eq 'destroy' ) {
		$variable{error} .= $Manifest->destroy();
		if ( ! $variable{error} ) {
			$variable{Redirect} = '/employee/inventory/manifests.html';
			%param = ();
		} # end if
	} elsif ( $param{btnFunction} eq 'Save' ) {
		$variable{error} = save_Manifest( $Manifest );
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/employee/inventory/manifest_view.html?manifest_id='.$Manifest->id();
		} # end if
	} elsif ( $param{btnFunction} eq 'ChangePaper' ) {
		foreach my $Type ( openprint::Manifest_Content_Type->find( manifest_id=>$Manifest->id()) ) {
			foreach my $MC ( $Manifest->Contents( type_id => $$Type{id} ) ) {
				$variable{error} .= $MC->fix();
			} # end foreach MC
		} # end foreach Type
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/employee/inventory/manifest.html?manifest_id='.$Manifest->id();
		} # end if
	} elsif ( $param{btnFunction} eq 'Submit' ) {
		$variable{error} = save_Manifest( $Manifest );
		$variable{error} .= apply_Manifest( $Manifest ) if ! $variable{error};

		if ( ! $variable{error} ) {
			$variable{information} .= 'Information successfully stored.<br/>';
			$variable{ExternalRedirect} = '/employee/inventory/manifest.html?manifest_id='.$Manifest->id();
		} # end if
		%param = ();
	} # end if btnfunction
	$variable{Manifest} = $Manifest;
} # end sub manifest

sub _manifest_contents {
	if ( ! $param{type_id} ) {
		$log->error( 'Loading _manifest_contents without type_id' );
	} # end if
	my $Type = $variable{Type} = new openprint::Manifest_Content_Type( $param{type_id} );
	if ( ( $Type->type() ne $param{"type-$$Type{id}"} ) and $param{"type-$$Type{id}"} ) {
		$Type->save({type => $param{"type-$$Type{id}"} });
	} # end if

	if ( ! $$Type{id} ) {
		$log->error( 'Loading _manifest_contents with invalid type_id' );
	} # end if
	$variable{Manifest} = $Type->Manifest();
	$variable{type_id} = $$Type{id};

	foreach my $Content ( openprint::ManifestContent->find( type_id=>$param{type_id} ) ) {
		my $quantity = $Type->type() eq 'Roll' ? $param{"qty_lbs-$$Type{id}-$$Content{id}"} : $param{"qty_sheets-$$Type{id}-$$Content{id}"};

		if ( ( $Content->skid_id != $param{"skid_id-$$Type{id}-$$Content{id}"} ) and ( $Content->quantity() != $quantity ) ) {
if ( 0 ) {
			$variable{error} .= $Content->save({
				skid_id		=>	$param{"skid_id-$$Type{id}-$$Content{id}-$$Content{id}"},
				quantity	=>	$quantity,
			});
} else {
$log->debug("WOuld update");
}
		} else {
			$log->debug("No save needed for " . $Content->to_string() );
		} # end if
	} # end foreach Content
} # end sub _manifest_contents

sub _manifest_content {
	if ( $param{action} eq 'Remove' ) {
		my $C = new openprint::ManifestContent( $param{content_id} );
		if ( $$C{id} ) {
			$variable{type_id} = $C->type_id();
			$variable{Manifest} = $C->Manifest();
			$variable{error} .= $C->delete();
		} # end if
	} elsif ( $param{action} eq 'Fix' ) {
		my $MC = $variable{C} = new openprint::ManifestContent( $param{content_id} );
		$variable{error} .= $MC->fix();
		$variable{type_id} = $MC->type_id();
		$variable{Manifest} = $MC->Manifest();
	} elsif ( $param{action} eq 'Apply' ) {
		my $MC = $variable{C} = new openprint::ManifestContent( $param{content_id} );
		$variable{error} .= $MC->apply();
		$variable{type_id} = $MC->type_id();
		$variable{Manifest} = $MC->Manifest();
	} elsif ( $param{action} eq 'Add' ) {
		# The goal is to store as much info as possible in the manifest, but not commit to the other objects until we Submit the manifest.
		if ( ! $param{manifest_id} ) {
			$variable{error} .= 'No manifest id. Please enter the manifest id before adding items to it.<br/>';
			return;
		} # end if
		my $Type = new openprint::Manifest_Content_Type( $param{type_id} );
		if ( ! $Type->id() ) {
			$variable{error} .= 'No type.  This should not happen.<br/>';
			return;
		} # end if
		my $Manifest = $variable{Manifest} = new openprint::Manifest( $param{manifest_id} );
		if ( $param{manifest_id} and ! $Manifest->id() ) {
			$variable{error} .= $Manifest->save({ id=>$param{manifest_id} });
		} # end if

		if ( ! ( $param{rfidtag_id} or $param{skid_id} or $param{manufacturers_id} or $param{quantity} ) ) {
			$variable{error} .= 'No RFID, Skid ID or manufacturers ID or quantity given.  No changes made.<br/>';
			return;
		} # end if

		@param{'rfidtag_id','skid_id','manufacturers_id'} = misc::trim(@param{'rfidtag_id','skid_id','manufacturers_id'});
		my $Skid = new openprint::Skid( $param{skid_id} );

		my $Tag = new openprint::RFIDTag( $param{rfidtag_id} );
		if ( $param{rfidtag_id} and ! $Tag->id() ) {
			my $invalid = openprint::RFIDTag::is_invalid_id($param{rfidtag_id});
			if ( ! $invalid ) {
				$Tag->save({id=>$param{rfidtag_id}});
			} else {
				$variable{error} .= 'RFID Tag appears to be invalid: ' . $invalid.'<br/>';
				$Tag->id($param{rfidtag_id});
			} # end if
		} elsif ( $Tag->id() ) {
			$Skid = $Tag->Skid() if $Tag->id() and ! $Skid->id();
		} # end if

		if ( $Skid->id() and $Tag->id() and $Skid->rfidtag_id() and ( $Skid->rfidtag_id() != $Tag->id() ) ) {
			$variable{error}  .= "Skid $$Skid{id} already has RFID Tag " . $Skid->rfidtag_id(). '.<br/>';
		} # end if

		if ( $param{manufacturers_id} ) {
			my $S = openprint::Skid->find_one(manufacturers_id=>$param{manufacturers_id} );

			if ( ! $Skid->id() ) {
				$Skid = $S if $S;
			} elsif ( ! $Skid->manufacturers_id() ) {
				if ( $Skid->id() != $S->id() ) {
					$variable{error} .= 'Manufacturers id '.$param{manufacturers_id}. ' has already been assigned to <a href="/employee/inventory/skid_details.html?skid_id='.$S->id().'">'.$S->id().'</a>.<br/>';
				} # end if
			} # end if
# FIXME: Should look at paper type as well.
		} # end if

		if ( ( ! $Tag->id() ) and $Skid and $Skid->rfidtag_id() ) {
			$Tag = $Skid->RFIDTag();
		} # end if

		if ( $Tag->id() and sets::isin( $Tag->id(), [ map { $_->rfidtag_id() } $Manifest->Contents() ] ) ) {
			$variable{error} .= 'RFID Tag ' . $Tag->id() . ' has already been entered.';
		} elsif ( $Skid->id() and sets::isin( $Skid->id(), [ map { $_->skid_id() } $Manifest->Contents() ] ) ) {
			$variable{error} .= 'Skid ' . $Skid->id(). ' has already been entered.';
		} elsif ( $param{manufacturers_id} and sets::isin( $param{manufacturers_id}, [ map { $_->manufacturers_id() } $Manifest->Contents() ] ) ) {
			$variable{error} .= 'Manufacturers id ' . $param{manufacturers_id} . ' has already been entered.';
		} # end if

		my $MC = new openprint::ManifestContent();
		if ( $$Skid{id} ) {
# Now check for warnings
			#if ( my $otherMC = openprint::ManifestContent->find_one( skid_id=>$$Skid{id}) ) {
				#$variable{warning} .= 'Warning: Skid ' . $Skid->id(). ' is also on manifest '.$otherMC->Manifest()->name().'.';
			#} # end if

# Auto load data
			my @SC = $Skid->Contents();
			if ( ! $param{qty_lbs} ) {
				if ( @SC == 1 ) {
					$param{qty_lbs} = $SC[0]->quantity();
				} # end if
			} # end if
			if ( ! $param{location_id} ) {
				$param{location_id} = $Skid->location_id();
			} # end if
		} # end if
		$variable{error} .= $MC->save( {
				type_id		=>	$param{type_id},
				Skid		=>	$Skid,
				rfidtag_id	=>	$Tag->id(),
				manifest_id	=>	$Manifest->id(),
				manufacturers_id	=>	$param{manufacturers_id},
				docket		=>	$param{docket},
				quantity	=>	Math::Round::nearest( 1, $param{quantity} ),
				location_id	=>	$param{location_id},
				} );
		$variable{C} = $MC;
		$variable{type_id} = $param{type_id};
		$variable{Type} = $Type;
	} # end if
} # end sub _manifest_content

sub manifests {
	_manifests();
	ssi::setup_date_select( '/employee/inventory/manifests.html', 'received_on_start', -7 );
	ssi::setup_date_select( '/employee/inventory/manifests.html', 'received_on_end', '' );
	ssi::setup_date_select( '/employee/inventory/manifests.html', 'created_on_start', -7 );
	ssi::setup_date_select( '/employee/inventory/manifests.html', 'created_on_end', '' );
	$session{'/employee/inventory/manifests.html?deleted'} = '0' if ! exists $session{'/employee/inventory/manifests.html?deleted'};
	$session{'/employee/inventory/manifests.html?has'} = '' if ! exists $session{'/employee/inventory/manifests.html?has_errors'};
} # end sub manifests

sub _manifests {
  if ($param{btnFunction}) {
    if ( $param{btnFunction} eq 'delete' ) {
      foreach my $manifest_id ( ref $param{manifest_id} eq 'ARRAY' ? @{$param{manifest_id}} : split(',',$param{manifest_id}) ) {
        my $Manifest = new openprint::Manifest( $manifest_id );
        $variable{error} .= $Manifest->delete();
      } # end foreach manifest_id
    } elsif ( $param{btnFunction} eq 'undelete' ) {
      if (exists $param{'manifest_id[]'}) {
        foreach my $manifest_id ( @{$param{'manifest_id[]'}} ) {
          my $Manifest = new openprint::Manifest( $manifest_id );
          next if !$Manifest->deleted();
          $variable{error} .= $Manifest->undelete();
        } # end foreach manifest_id
      } else {
        foreach my $manifest_id ( ref $param{manifest_id} eq 'ARRAY' ? @{$param{manifest_id}} : split(',',$param{manifest_id}) ) {
          my $Manifest = new openprint::Manifest( $manifest_id );
          next if !$Manifest->deleted();
          $variable{error} .= $Manifest->undelete();
        } # end foreach manifest_id
      }
    } elsif ( $param{btnFunction} eq 'destroy' ) {
      if (exists $param{'manifest_id[]'}) {
        foreach my $manifest_id ( @{$param{'manifest_id[]'}} ) {
          my $Manifest = new openprint::Manifest( $manifest_id );
          next if !$Manifest->deleted();
          $variable{error} .= $Manifest->destroy();
        } # end foreach manifest_id
      } else {
        foreach my $manifest_id ( ref $param{manifest_id} eq 'ARRAY' ? @{$param{manifest_id}} : split(',',$param{manifest_id}) ) {
          my $Manifest = new openprint::Manifest( $manifest_id );
          next if !$Manifest->deleted();
          $variable{error} .= $Manifest->destroy();
        } # end foreach manifest_id
      } # end if
    } # end if
  } # end if
	ssi::save_params( '/employee/inventory/manifests.html', ( 
				( map { 'received_on_start_'.$_ } ( 'year','month','day' ) ),
				( map { 'received_on_end_'.$_ } ( 'year','month','day' ) ),
				( map { 'created_on_start_'.$_ } ( 'year','month','day' ) ),
				( map { 'created_on_end_'.$_ } ( 'year','month','day' ) ),
				( map { 'updated_on_start_'.$_ } ( 'year','month','day' ) ),
				( map { 'updated_on_end_'.$_ } ( 'year','month','day' ) ),
				'supplier_id', 'delivery','deleted','has_errors','type','po_confirmed',
				) );
	if ( ! exists $param{type} ) {
		delete $session{'/employee/inventory/manifests.html?type'};
	} # end if
} # end sub _manifests

sub inventory_log {
	if ( $param{btnFunction} eq 'Download' ) {
		my @Header = ('When','Who', 'Skid','RFIDTag','Paper','Amount','Allocated','In Stock','Location','Comment' );
		my @Data;

		my @PIs = openprint::PaperInventory->find(
			ssi::date_filter( 'updated_on_start', 'updated_on >=', \%param ),
			ssi::date_filter( 'updated_on_end', 'updated_on <=', \%param ),
			($param{employee_id} ? ( user_id		=>	$param{employee_id} ) : () ),
				( $param{'delta_upper'} ? ( 'delta <=' => $param{delta_upper} ) : () ),
				( $param{'delta_lower'} ? ( 'delta >=' => $param{delta_lower} ) : () ),
		);
		$log->debug("# of inventory entries: " . @PIs );
		my $total = 0;
		my %locations = map { $_, $_ } ( ref $param{location_id} eq 'ARRAY' ? @{$param{location_id}} : ($param{location_id}) );
		my %types = map { $_, $_ } ( ref $param{Type} eq 'ARRAY' ? @{$param{Type}} : ($param{Type}) );
		foreach my $PI ( @PIs ) {
			if ( $PI->delta < 0 and ! $param{outs} ) {
				$log->debug("Not wanting outs");
				next;
			}
			if ( $PI->delta > 0 and ! $param{ins} ) {
				$log->debug("Not wanting ins");
				next;
			}
			my $Paper = $PI->Paper();
			if ( $Paper->type() and ! $types{$Paper->type()} ) {
				$log->debug("Not in types " . join(',', keys %types ) );
				next;
			} # end if
			if ( ( ! $Paper->type() ) and ! $types{Unknown} ) {
				$log->debug("Unknnown type");
				next;
			} # end if
			my $Skid = $PI->Skid();
			if ( ( ! $locations{All} ) and ! $locations{$Skid->Location()->Root()->id()} ) {
				$log->debug("Not in locations: " . $Skid->Location()->Root()->name() . ' in ' . join(',', keys %locations ) );
				next;
			} # end if
			
			push @Data, (
				Date::Format::time2str('%Y-%m-%d %H:%M', Date::Parse::str2time($PI->updated_on) ),
				$PI->User()->name(),
				$PI->skid_id,
				$Skid->RFIDTag()->id_short(),
				$Paper->to_string(),
				$PI->delta,
				join(',', map { sprintf('%d%s to %d', $_->quantity(),$_->units(), $_->docket() ) } openprint::PaperAllocation->find( 'skid_ids any'=>$PI->skid_id, paper_id=>$PI->paper_id)),
				$PI->instock,
				$Skid->Location()->name(),
				$PI->comment,
				);
			$total += $PI->delta;
		} # end while
		push @Data, '','','','','Totals:',$total,'','','','';
		misc::export_csv( $r, $log, \%variable, 'InventoryLog.csv', \@Header, \@Data );
	} # end if
	if ( ! exists $session{'/employee/inventory/inventory_log.html?ins'} ) {
		$session{'/employee/inventory/inventory_log.html?ins'} = 1;
	} # end if
	if ( ! exists $session{'/employee/inventory/inventory_log.html?outs'} ) {
		$session{'/employee/inventory/inventory_log.html?outs'} = 1;
	} # end if
	ssi::setup_date_select( '/employee/inventory/inventory_log.html', 'updated_on_start', 0 );
	ssi::setup_date_select( '/employee/inventory/inventory_log.html', 'updated_on_end', 0 );
	
	ssi::save_params( '/employee/inventory/inventory_log.html', ( 
				( map { 'updated_on_start_'.$_ } ( 'year','month','day', 'hour', 'minute' ) ),
				( map { 'updated_on_end_'.$_ } ( 'year','month','day', 'hour', 'minute' ) ),
				( 'ins', 'outs', 'Type', 'location_id', 'manifests_within_days', 'show_manifests' ) ) );
	$session{'/employee/inventory/inventory_log.html?manifests_within_days'} = 7 if ! defined $session{'/employee/inventory/inventory_log.html?manifests_within_days'};
	$session{'/employee/inventory/inventory_log.html?manifests_within_lbs'} = 100 if ! defined $session{'/employee/inventory/inventory_log.html?manifests_within_lbs'};
	$session{'/employee/inventory/inventory_log.html?show_manifests'} = 0 if ! defined $session{'/employee/inventory/inventory_log.html?show_manifests'};
	$session{'/employee/inventory/inventory_log.html?show_stock_on_manifests'} = 0 if ! defined $session{'/employee/inventory/inventory_log.html?show_stock_on_manifests'};
	$session{'/employee/inventory/inventory_log.html?Type'} = join(',', ( 'Sheet','Roll','Unknown') ) if ! defined $session{'/employee/inventory/inventory_log.html?Type'};
} # end sub inventory_log

sub _inventory_log {
	ssi::save_params( '/employee/inventory/inventory_log.html', ( 
( map { 'updated_on_start_'.$_ } ( 'year','month','day', 'hour', 'minute' ) ),
( map { 'updated_on_end_'.$_ } ( 'year','month','day', 'hour', 'minute' ) ),
( 'ins', 'outs', 'Type', 'location_id', 'manifests_within_days', 'manifests_within_lbs','show_manifests', 'employee_id',
'delta_lower','delta_upper' ) ) );
	$session{'/employee/inventory/inventory_log.html?ins'} = $param{ins};
	$session{'/employee/inventory/inventory_log.html?outs'} = $param{outs};
	$session{'/employee/inventory/inventory_log.html?show_stock_on_manifests'} = $param{show_stock_on_manifests};

	$variable{Skid} = new openprint::Skid( $param{skid_id} );
} # end sub inventory_log

sub _paper_allocations {
	$param{paper_id} = openprint::Paper->transform( 'id', $param{paper_id} );
	$variable{Paper} = new openprint::Paper( $param{paper_id} );
	if ( $param{action} eq 'Add' ) {
		$param{skid_id} = openprint::Skid->transform( 'id', $param{skid_id} );
		$param{Docket} =~ openprint::Order->transform( 'docket', $param{Docket} );
		$param{AllocationQuantity} =~ s/[^\d\-]//g;
		my $Order = openprint::Order->find_one( docket=>$param{Docket} ) if $param{Docket};

		if ( ! $Order ) {
			$variable{error} .= "Docket $param{Docket} not found.<br/>";
		} else {
			$variable{Paper}->allocate( $param{skid_id}, $Order->docket(), $param{AllocationQuantity} );
		} # end if
		delete $param{skid_id};
	} elsif ( $param{action} eq 'Delete Allocation' ) {
		if ( $param{allocation_id} ) {
			my $PA = new openprint::PaperAllocation( $param{allocation_id} );
			$variable{error} .= $PA->delete($param{reason});
		} # end if
	} # end if
} # end sub _paper_allocations

sub _skid_allocations {
	$variable{skid_id} = $param{skid_id};
	my $Skid = $variable{Skid} = new openprint::Skid( $param{skid_id} );

    if ( $param{action} eq 'Add' ) {
		$param{paper_id} = openprint::Paper->transform( 'id', $param{paper_id} );
		$param{Docket} =~ openprint::Order->transform( 'docket', $param{Docket} );
        my $Paper = new openprint::Paper( $param{paper_id} );
		if ( ! $Paper ) {
			$variable{error} .= "Paper not found.<br/>";
			return;
		} # end if

		my $Order = openprint::Order->find_one( docket=>$param{Docket} ) if $param{Docket};
		if ( ! $Order ) {
			$variable{error} .= "Docket $param{Docket} not found.<br/>";
			return;
		} # end if

        if ( $Skid->allocateable() < $param{AllocationQuantity} ) {
            $variable{error} .= 'Only ' .  $Skid->allocateable() . ' on this skid. No paper allocated.<br/>';
        } else {
            $Paper->allocate( $Skid, $Order->docket(), @param{'AllocationQuantity','Units'} );
            $variable{information} .= sprintf('Allocated %s%s to docket %d<br/>', @param{'AllocationQuantity','Units'}, $Order->docket() );
        } # end if
    } elsif ( $param{action} eq 'delete' ) {
        my $Allocation = new openprint::PaperAllocation( $param{allocation_id} );
		if ( $Allocation->id() ) {
			$Allocation->Order()->add_log( 'Paper Allocation for ' . $Skid->link_to() . ' deleted.' );
			$Allocation->delete();
		} else {
			$openprint::log->warn('Non-existent Paper Allocation deleted.');
		} # end if
	} # end if
} # end sub _skid_allocations


sub available_paper {
	if ( $param{btnFunction} eq 'Allocate' ) {
		if ( exists $param{Captcha} ) {
	# Remove spaces, because some people want to put spaces between the characters, etc.
			$param{Captcha} =~ s/\s//g;
			my $Captcha = new Authen::Captcha(
						data_folder => $config{SkinPath}.'/tmp',
						output_folder => $config{SkinPath}.'/images/captcha'
						);
			if ( 1 != $Captcha->check_code(@param{'Captcha','MD5SUM'}) ) {
				$variable{error} .= 'Captcha Validation Code incorrect.	Please try again.';
				return;
			} # end if
		} # end if
		foreach my $condition_id ( sets::union( map { $_->condition_id() } openprint::SkidContent->find(deleted=>0,paper_id=>$param{paper_id},'quantity >' =>0 ) ) ) {
			next if ! $param{'quantity-'.$condition_id};
			allocate( @param{'skid_id','paper_id','quantity-'.$condition_id,'Project','Docket','specific','reason'}, $condition_id );
		} # end foreach condition
		@session{'error','warning','information'} = @variable{'error','warning','information'};
		$variable{ExternalRedirect} = '/employee/inventory/available_paper.html';
		%param = ();
	} # end if
	$session{'/employee/inventory/available_paper.html?owner_id_exclude'} = $param{owner_id_exclude} if exists $param{owner_id};
	$session{'/employee/inventory/available_paper.html?type'} = 'Roll' if ! $session{'/employee/inventory/available_paper.html?type'};
	$session{'/employee/inventory/available_paper.html?exlude_press_feed'} = '1' if ! $session{'/employee/inventory/available_paper.html?exclude_press_feed'};
	if ( ! exists $session{'/employee/inventory/available_paper.html?condition_id'} ) {
		my $New = openprint::InventoryCondition->find_one( name=>'new' );
		$session{'/employee/inventory/available_paper.html?condition_id'} = $New->id() if $New;
	} # end if
	_available_paper();
	if ( $param{btnFunction} eq 'Download' ) {
		my @header = ('Paper', 'Available','Age', 'Last Seen','Condition','Inventory');
		my @data;

		my @location_ids;
		foreach my $location_id ( split(',', $session{$r->uri().'?location_id'} ) ) {
			if ( $location_id eq 'All' ) {
				@location_ids = ();
				last;
			} # end if
			next if (! $location_id) or ( $location_id eq '' );
			push @location_ids, $location_id;
		} # end foreach
		my %location_ids = map { $_, $_ } @location_ids;
		my $total_weight;
		my $total_rolls;
		my $total_sheets;
		my $total_skids;
		my $available_weight;
		my $available_sheets;
		my %Press_Feed_Locations;

		if ( $session{'/employee/inventory/available_paper.html?exclude_press_feeds'} eq '1' ) {
			foreach my $Equipment ( openprint::Equipment->find( 'category any'=>'Printing' ) ) {
				$Press_Feed_Locations{$Equipment->location_id()} = 1;
				$log->debug("Excluding " . $Equipment->Location()->name() );
			}
		}

		my @SkidContents = openprint::SkidContent->find(
				'condition not in' => ['Damaged','Used'],
				paper_id=>$variable{paper_ids},
				deleted=>0,
				'location not in' => 'Missing',
				'quantity >' => 1
				);
		my %SkidContents;
		my %SkidContentsByPaper;
		my @skid_ids = map { $$_{skid_id} } @SkidContents;
		my %Skids = map { $$_{id}, $_ } openprint::Skid->find(id=>\@skid_ids) if @skid_ids;
		my %SkidsByPaper;

		foreach my $SC ( @SkidContents ) {
			push @{$SkidContents{$$SC{skid_id}}}, $SC;
			push @{$SkidContentsByPaper{$$SC{paper_id}}}, $SC;
#push @{$SkidsByPaper{$$SC{paper_id}}}, $SC->Skid();
			push @{$SkidsByPaper{$$SC{paper_id}}}, $Skids{$$SC{skid_id}};
		} # end foreach SC

		foreach my $Paper ( @{$variable{Papers}} ) {
			my $in_stock = misc::sum( map { $_->quantity() } @{$SkidContentsByPaper{$$Paper{id}}} ) if $SkidContentsByPaper{$$Paper{id}};
			if ( ( $in_stock - $Paper->allocated() ) <= 0 ) {
				next;
			} # end if

			$Paper->available( int($in_stock - $Paper->allocated()) );
			my %skid_age;
			my %last_seen;
			my %skid_location;
			my %inventory;
			my %conditions;
			my $skids = 0;
			my @Skids = @{$SkidsByPaper{$$Paper{id}}} if $SkidsByPaper{$$Paper{id}};

			foreach my $Skid ( @Skids ) {
				$Skid->Contents( $SkidContents{$$Skid{id}} ? $SkidContents{$$Skid{id}} : [] );
				if ( $session{'/employee/inventory/available_paper.html?last_seen'} ) {
					next if $Skid->last_seen_days() > $session{'/employee/inventory/available_paper.html?last_seen'};
				} # end if
				if ( $session{'/employee/inventory/available_paper.html?condition_id'} ) {
					my $keep = 0;

					foreach my $C ( $Skid->Contents() ) {
						if ( $$C{'condition_id'} == $session{'/employee/inventory/available_paper.html?condition_id'} ) {
							$keep = 1;
							last;
						} # end if
					} #  end foreach
					next if ! $keep;
				} # end if

				if ( $session{'/employee/inventory/available_paper.html?exclude_press_feeds'} eq '1' ) {
					next if $Press_Feed_Locations{$Skid->location_id()};
				} # end if

				my $root_id = $Skid->Location()->Root(type=>'place')->id();
				if ( @location_ids ) {
					my @parent_ids = sets::union( map { $$_{id} } ( $Skid->Location(), $Skid->Location()->Parents() ) );
#$log->debug("Parents: @parent_ids" );
					my @intersect = sets::intersection( @location_ids, @parent_ids );
					if ( ! @intersect ) {
						$log->debug("Next because @parent_ids is not in location_ids (@location_ids) intersection: ( @intersect )");
						next;
					} elsif( ( ! $root_id ) and ! $location_ids{'Unknown'} ) {
						$log->debug("No unknown");
						next;
					} # end if
				} # end if
				$skid_age{$Skid->age_days()} += 1;
				$last_seen{$Skid->last_seen_days()} += 1;
				foreach my $C ( $Skid->Contents() ) {
					$conditions{$$C{condition_id}} += 1;
				} # end foreach Content
				$skids += 1;

				$skid_location{$root_id} += 1;
				$inventory{$root_id} += $Skid->contents($Paper);
			} # end foreach Skid
			if ( ! $skids ) {
				$log->warn('No skids');
				next;
			} # end if

			if ( $Paper->type() eq 'Roll' ) {
				$total_weight += $in_stock;
				$total_rolls += @Skids;
				$available_weight += $Paper->available();
			} else {
				$total_sheets += $in_stock;
				$total_skids += @Skids;
				$available_sheets += $Paper->available();
			} # end if
			push @data, (
					$Paper->to_string(),
					Number::Format::format_number($Paper->available()) . $Paper->units( $Paper->available() ),
					join(',', map { $_.'days - ' . $skid_age{$_} . $Paper->types($skid_age{$_}) } keys %skid_age),
					join(',', map { $_.'days - ' . $last_seen{$_} . $Paper->types($last_seen{$_}) } keys %last_seen),
					join(',', map { new openprint::InventoryCondition($_)->name().' - ' . $conditions{$_} . $Paper->types($conditions{$_}) } keys %conditions),
					join(',', map { ($_ ? new openprint::Location($_)->name() : 'unknown' ).' - ' . $skid_location{$_} . $Paper->types($skid_location{$_}). ' - ' . Number::Format::format_number($inventory{$_}).'lbs' } keys %skid_location),
					);
		} # end foreach Paper

		push @data, ('Totals:',
				join(', ',
					( $available_weight ? Number::Format::format_number($available_weight).'lbs' : () ),
					( $available_sheets ? Number::Format::format_number($available_sheets).'sheets' : () ),
					), ' ', '', '',
				join(', ',
					( $total_weight ? Number::Format::format_number($total_rolls).'rolls ' . Number::Format::format_number($total_weight).'lbs' : () ),
					( $total_sheets ? Number::Format::format_number($total_skids).'skids ' . Number::Format::format_number($total_sheets).'sheets' : () ),
					));
		my $date = Date::Format::time2str('%Y-%m-%d %H:%M', time);
		push @data, ('Report generated: '.$date, '', '', '', '', '', '');
		misc::export_csv($r, $log, \%variable, 'AvailablePaper.csv', \@header, \@data);
	} # end if Download
} # end sub available_paper

sub _available_paper {
	my $uri = '/employee/inventory/available_paper.html';
	ssi::save_params( $uri,
			'owner_id', 'manufacturer_id', 'brand_id', 'finish_id', 'colour_id', 'weight_id', 
			'material_id','quality_id','group_id','condition_id',
			'width','height','OrLarger', 'type', 'fsc_code', 'last_seen', 'location_id', 'unmatched', 'exclude_press_feeds' );
	$session{$uri.'?owner_id_exclude'} = $param{owner_id_exclude} if exists $param{owner_id};
	$session{$uri.'?type'} = 'Roll' if ! $session{$uri.'?type'};
	$session{$uri.'?OrLarger'} = $param{OrLarger};
	use constant DEBUG => 0;
	openprint::StockBrand->find();
	openprint::StockFinish->find();
	openprint::StockWeight->find();
	openprint::Manufacturer->find();
	my %sql = (
			'in_stock >'  =>  1,
			type          =>  [ split( ',', $session{$uri.'?type'} ) ],
			columns         =>  '*,(SELECT SUM(quantity) FROM paper_allocations WHERE paper_id=papers.id) AS allocated',
			( $session{$uri.'?OrLarger'} ne 'Y' ? (
																						 ( $session{$uri.'?width'} ? ( width=>$session{$uri.'?width'} ) : () ),
																						 ( $session{$uri.'?height'} ? ( height=>$session{$uri.'?height'} ) : () ),
																						) : (
																							( $session{$uri.'?width'} ? ( 'width >='=>$session{$uri.'?width'} ) : () ),
																							( $session{$uri.'?height'} ? ( 'height >='=>$session{$uri.'?height'} ) : () ),
																							) ),
			);
	foreach my $filter ( 'owner_id','manufacturer_id','brand_id','finish_id','colour_id','weight_id','quality_id', 'material_id', 'group_id' ) {
		if ( $session{$uri.'?'.$filter} ) {
			if ( $session{$uri.'?'.$filter.'_exclude'} ) {
				$sql{$filter.' !='} = $session{$uri.'?'.$filter};
			} else {
				$sql{$filter} = $session{$uri.'?'.$filter};
			} # end if
		} # end if
	} # end foreach filter
	$variable{Papers} = [ sort {
		$_ = lc $a->manufacturer cmp lc $b->manufacturer;
		return $_ if $_;
		$_ = lc $a->brand cmp lc $b->brand;
		return $_ if $_;
		$_ = lc $a->finish cmp lc $b->finish;
		return $_ if $_;
		$_ = $a->weight <=> $b->weight;
		return $_ if $_;
		$_ = $$a{width} <=> $$b{width};
		return $_ if $_;
		$_ = $$a{height} <=> $$b{height};
		return $_ if $_;

	} openprint::Paper->find(%sql) ];
	my @paper_ids = @{$variable{paper_ids}} = map { $$_{id} } @{$variable{Papers}};
	my %SkidContents;

	if ( @paper_ids ) {
		foreach my $SC ( openprint::SkidContent->find( paper_id=>\@paper_ids, 'quantity >' => 1 ) ) {
			push @{$SkidContents{$$SC{paper_id}}}, $SC;
		} # end foreach
	}
	foreach my $Paper ( @{$variable{Papers}}  ) {
		$Paper->SkidContents( $SkidContents{$$Paper{id}} );
	} # end foreach Paper
	if ( DEBUG ) {
		foreach my $Paper ( @{$variable{Papers}}  ) {
			$log->debug("Initial Papers: " . $Paper->to_string() );
		}
	}
	openprint::Location->find(company_id=>$openprint::User->company_id());
} # end sub _available_paper

sub _allocate_popup {
	if ( $param{referer} ) {
		$variable{referer} = $param{referer};
	} elsif ( $ENV{HTTP_REFERER} ) {
		$log->debug($ENV{HTTP_REFERER});
		$ENV{HTTP_REFERER} =~ /.*\/(.*\.html)/;
		$variable{referer} = $1;
	} # end if
	$variable{Paper} = new openprint::Paper( $param{paper_id} );
	if ( exists $param{quantity} ) {
		$variable{quantity} = $param{quantity};
	} else {
		$variable{quantity} = $variable{Paper}->available();
	} # end if
} # end sub _allocate_popup

sub _manifest_purchase_orders {
	$variable{Type} = new openprint::Manifest_Content_Type($param{type_id});
} # end sub _manifest_purchase_orders

sub _manifest_purchase_order_contents {
	$variable{Type} = new openprint::Manifest_Content_Type($param{type_id});
	$variable{Type}->po_id($param{po_id});
} # end sub _manifest_purchase_order_contents

sub _rfidtag_log {
	if ( ! exists $param{start_year} ) {
		my $Entry = openprint::RFIDTagHistory->find_one( 
			( $param{rfidtag_id} ? ( rfidtag_id	=>	$param{rfidtag_id} ) : () ),
			( $param{scanner_id} ? ( scanner_id	=>	$param{scanner_id} ) : () ),
			order		=>	'updated_on DESC',
			limit		=>	$param{limit},
			);
		if ( $Entry ) {
			@param{'start_year','start_month','start_day'} = $Entry->updated_on() =~ /^(\d+)-(\d+)-(\d+)/;
		} # end if
	} # end if

} # end sub _rfidtag_log

sub _rfidtag_log_entries {
} # end sub _rfidtag_log_entries

sub _verification_log {
	$variable{Skid} = new openprint::Skid( $param{skid_id} );
} # end sub _verification_log

sub paper_label_window {
} # end sub paper_label_window

sub move_skids_window {
} # end sub move_skids_window

sub allocations {
	if ( $param{action} ) {
		if ( $param{action} eq 'Reset' ) {
			ssi::reset_session($variable{uri});
		}
	}
	_allocations();
	if ( ! exists $session{$variable{uri}.'?Type'} ) {
		$session{$variable{uri}.'?Type'} = 'Roll,Sheet';
	}
		
} # end sub allocations

sub _allocations {
	ssi::save_params( '/employee/inventory/allocations.html', ( 
		'Type', 'company_id','salesrep_id',
( map { 'created_on_start_' . $_ } ( 'year','month','day' ) ),
( map { 'created_on_end_' . $_ } ( 'year','month','day' ) ),
( map { 'stock_age_start_' . $_ } ( 'year','month','day' ) ),
( map { 'stock_age_end_' . $_ } ( 'year','month','day' ) ),
'Docket', ) );
	if ( $param{action} eq 'Delete' ) {
		my @ids = map { split(',', $_ ) } ( ( ref $param{allocation_id} eq 'ARRAY' ) ? @{$param{allocation_id}} : $param{allocation_id} );
		@ids = map { openprint::PaperAllocation->transform( id=>$_ ) } @ids;
$log->debug("Ids: @ids");
		if ( @ids ) {
			foreach my $Allocation ( openprint::PaperAllocation->find( id=>\@ids ) ) {
				$variable{error} .= $Allocation->delete();
			}
		}
	}
} # end sub _allocations

sub _deallocate_popup {
}
sub _skids_results {
	ssi::save_params( '/employee/inventory/skids.html', ( 
				( map { 'received_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'received_on_end_' . $_ } ( 'year','month','day' ) ),
				( map { 'created_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'created_on_end_' . $_ } ( 'year','month','day' ) ),
				( map { 'updated_on_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'updated_on_end_' . $_ } ( 'year','month','day' ) ),
				( map { 'last_seen_start_' . $_ } ( 'year','month','day' ) ),
				( map { 'last_seen_end_' . $_ } ( 'year','month','day' ) ),
	
				'Docket','fsc_code','empty', 'rfid','rfid_valid','location_id','verification_code', 'allocated','contents','hasmanifest',
				'condition_id', 'skid_id', 'rfid_id', 'manufacturers_id', 'hasmanufacturers','deleted','checked_out','type','has_value',

				'manufacturer_id','brand_id','finish_id','colour_id','weight_id','quality_id',
                'owner_id','material_id','group_id', 'condition_id',
                'width','height','OrLarger','owner_id_exclude',
				'inventory_check_id', 'inventory_check_id_exclude',
            ) );
    $session{'/employee/inventory/skids.html?owner_id_exclude'} = $param{owner_id_exclude} if exists $param{owner_id};
    $session{'/employee/inventory/skids.html?inventory_check_id_exclude'} = $param{inventory_check_id_exclude};
    $session{'/employee/inventory/skids.html?OrLarger'} = $param{OrLarger};
}

sub _paper_log {
	ssi::save_params( '/employee/inventory/paper_details.html', ( 'ddmStartYear','ddmStartMonth','ddmStartDay','ddmEndYear','ddmEndMonth','ddmEndDay','limit' ) );
} # end _paper_log
sub _skid_log {
} # end _skid_log

sub skid_label {
} # end sub skid_label

sub _check_out_popup {
} # end sub _check_out_popup

sub _add_paper_show {
} # end sub _add_paper_show
sub _add_paper_hide {
} # end sub _add_paper_hide

sub docket_labels {
} # end sub docket_labels

sub _check_in_popup {
} # end sub _check_in_popup

sub packingslips {
	_packingslips();
	ssi::setup_date_select( '/employee/inventory/packingslips.html', 'created_on_start', -7 );
	ssi::setup_date_select( '/employee/inventory/packingslips.html', 'created_on_end', '' );
	$session{'/employee/inventory/packingslips.html?deleted'} = '0' if ! exists $session{'/employee/inventory/packingslips.html?deleted'};
} # end sub packingslips

sub _packingslips {
  ssi::save_params( '/employee/inventory/packingslips.html', ( 'company_id','docket','type_id','deleted',
      'created_on_start_year','created_on_start_month','created_on_start_day',
      'created_on_end_year','created_on_end_month','created_on_end_day',
    ) );

  if ( $param{btnFunction} ) {
    if ( $param{btnFunction} eq 'delete' ) {
      foreach my $id ( ref $param{packingslips} eq 'ARRAY' ? @{$param{packingslips}} : split(',',$param{packingslips}) ) {
        my $Label = new openprint::Label( $id );
        $variable{error} .= $Label->delete();
      } # end foreach id
    } elsif ( $param{btnFunction} eq 'undelete' ) {
      if (exists $param{'packingslips[]'}) {
        foreach my $id ( @{$param{'packingslips[]'}} ) {
          my $Label = new openprint::Label( $id );
          next if !$Label->deleted();
          $variable{error} .= $Label->undelete();
        } # end foreach label_id
      } else {
        foreach my $id ( ref $param{packingslips} eq 'ARRAY' ? @{$param{packingslips}} : split(',',$param{packingslips}) ) {
          my $Label = new openprint::Label( $id );
          next if !$Label->deleted();
          $variable{error} .= $Label->undelete();
        } # end foreach
      }
    } elsif ( $param{btnFunction} eq 'destroy' ) {
      if (exists $param{'packingslips[]'}) {
        foreach my $id ( @{$param{'packingslips[]'}} ) {
          my $Label = new openprint::Label( $id );
          next if !$Label->deleted();
          $variable{error} .= $Label->destroy();
        } # end foreach id
      } else {
        foreach my $id ( ref $param{packingslips} eq 'ARRAY' ? @{$param{packingslips}} : split(',',$param{packingslips}) ) {
          my $Label = new openprint::Label( $id );
          next if !$Label->deleted();
          $variable{error} .= $Label->destroy();
        } # end foreach id
      } # end if
    } # end if
  }
} # end sub _packingslips

sub _rfidscanners_results {
} # end sub _rfidscanners_results

sub _map {
} # end sub _map

sub _docket_label {
} # end sub _docket_label

sub _paper_inventory_entries {
  $variable{Paper} = new openprint::Paper( $param{paper_id} );

  if ( $param{Action} eq 'Add' ) {
    my $Skid = new openprint::Skid( $param{skid_id} );
    my $Paper = new openprint::Paper( $param{paper_id} );
    my $Condition = new openprint::InventoryCondition( $param{condition_id} );
    $Skid->location_id( $param{Location} );
    $Skid->add( $Paper, $param{quantity}, $Condition );
    $Skid->save();
          $Paper->add_inventory( $Skid->id(), $param{quantity} );
        } # end if
      } # end sub _paper_inventory_entries

      sub manifest_import {
        if ( my $upload = $r->upload('import') ) {
          require openprint::Manifest_Import_Rule;
          my %Rules = map { $_->match(), $_ } openprint::Manifest_Import_Rule->find();

          my $io =$upload->io();
          if ( $upload->filename() =~ /txt$/i ) {

			@{$variable{Types}} = ();

			my ( $width, $basis_weight, $product, $manufacturer );
			my $line_count = 1;
			my $roll_count = 0;
			my $Type;
			my $Manifest = $variable{Manifest} = new openprint::Manifest();
			$variable{error} .= $Manifest->save({name=>$param{import}});

			while ( my $line = <$io> ) {
				s/^\s+//, s/\s+$//, s/\s+/ /g, s/\.\s+/\./g for $line;

				if ( $line =~ /(.+)Page\s+(\d+) of (\d+)$/ ) {
					# Start a new page
					$log->debug("Line $line_count: Starting new page for $1 page $2 of $3");
				} elsif ( my ( $d, $m, $y, $H, $M ) = $line =~ /.+\s+(\d\d)\.(\d\d)\.(\d\d)\s*(\d\d:\d\d)$/ ) {
					$log->debug("Line $line_count: Date: $y-$m-$d $H:$M");
				} elsif ( ( $product ) = $line =~ /^PRODUCT NUMBER\s+(.+)$/ ) {
					$log->debug("Line $line_count: Product ($product)");
				} elsif ( ( $manufacturer ) = $line =~ /^Customer[^A-Z]+([A-Z]+)\s+.+$/ ) {
					$manufacturer = $Rules{$manufacturer}->replacement() if $Rules{$manufacturer};
					$log->debug("Line $line_count: Manufacturer ($manufacturer)");
			
				} elsif ( 
					( $width, $basis_weight, my $manufacturers_id, my $location, my $received_on, my $available_quantity, my $available_lbs, my $hold_quantity, my $hold_lbs ) = 
					$line =~ /^([\d\s\/\.]+)X *([\d\/\.]+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S)RO\S+\s+(\S+)\s+(\S)RO\S+\s+([\d\.]+)$/ ) {
					if ( my ($n,$m) = $width =~ /(\d+)\/(\d+)/ ) {
						my $r = $n/$m;
						$r =~ s/\d+(\.\d+)/$1/;
						$width =~ s/$n\/$m/$r/;
					} # end if
					$width =~ s/\s//g;

					$available_quantity =~ s/l/1/;
					$available_quantity =~ s/[OD]/0/;
					$available_lbs =~ s/[^\d\.]//g;
					$hold_lbs =~ s/[^\d\.]//g;

					$manufacturers_id =~ s/[^A-Z0-9]//g;

					$log->debug("Line $line_count: width: $width, weight: $basis_weight, id: $manufacturers_id, qty: $available_quantity, lbs: $available_lbs");
					$roll_count += 1;
					my @Papers = openprint::Paper->find_one( manufacturers_name=>$product, width=>$width, basis_weight=>$basis_weight, manufacturer=>$manufacturer );
					$Type->save() if $Type;
					$Type = new openprint::Manifest_Content_Type();
					$Type->set({ manifest_id=> $$Manifest{id} } );
					if ( @Papers == 1 ) {
						$Type->paper_id( $Papers[0]->id() );
					} # end if
					$variable{error} .= $Type->save();
					push @{$variable{Types}}, $Type;

					my $Content = new openprint::ManifestContent();
					$variable{error} .= $Content->save({manifest_id=>$$Manifest{id}, type_id=>$$Type{id}, quantity=>$available_quantity });
					
				} elsif ( 
					my ( $manufacturers_id, $location, $received_on, $available_quantity, $available_lbs, $hold_quantity, $hold_lbs ) = 
						$line =~ /^(\S+)\s+(\S+)\s+([\d\.]+)\s+(\S)RO\S+\s+(\S+)\s+(\S)RO\S+\s+([\d\.]+)$/ ) {
					$log->debug("Line $line_count: width: $width, weight: $basis_weight, id: $manufacturers_id, qty: $available_quantity, lbs: $available_lbs");
					$roll_count += 1;
				} elsif ( my ( $total_rolls, $total_weight ) = $line =~ /^TOTALS:\s+Available Quantity\s+(\d+)\s+EA\s+Available\s+.+eight\s+([\d\,\.]+)$/ ) {
					if ( ! $Type ) {
						$variable{error} .= "Line $line_count: No Type yet for $product<br/>";
						$Type = new openprint::Manifest_Content_Type();
						$Type->set({ manifest_id=> $$Manifest{id} } );
					} # end if
					$Type->item_count( $total_rolls );
					if ( $roll_count != $total_rolls ) {
						$log->warn("Line $line_count: Roll count($roll_count) != total rolls: $total_rolls");
					} # end if
					$roll_count = 0;
				} else {
					$log->debug("Line $line_count: unparsed line: $line");
				} # end if
				$line_count += 1;
			} # end while io
		} elsif ( $upload->filename() =~ /csv$/i ) {
			require Text::CSV_XS;
			my $csv = Text::CSV_XS->new();
			$_ = <$io>; # drop the title row
			my $ac = sql::start_transaction( $dbh );
			my $Manifest = $variable{Manifest} = new openprint::Manifest();
			$variable{error} .= $Manifest->save({name=>$param{import}});

			@{$variable{Types}} = ();
			my $Type;
			my $product;
			my $item_count = 0;

			my %Skids_by_mfg;

			while ( my $line = <$io> ) {
				my $status = $csv->parse($line);        # parse a CSV string into fields
				my @data = misc::trim($csv->fields());
				#Cust Code,Invt Lev1,Invt Lev2,Invt Lev3,On Hand Qty,On Hand Wgt,On Ord Qty,On Rcpt Qty,Hold Non Ship Qty
				my ( $cust_code, $desc1, $desc2, $mfg_name, $on_hand_qty, $weight_qty ) = @data;
				if ( ! $cust_code ) {
					$variable{warning} .= "Invalid line ($line)<br/>";
					next;
				} # end if
				my ( $width, $weight ) = ( $1, $2 );
				if ( $desc2 =~ /^([\.\d]+)\s?X\s?([\.\d]+)$/ ) {
					( $width, $weight ) = ( $1, $2 );
				} # end if
				if ( $product ne $desc1.' '.$desc2 ) {
					$variable{error} .= $Type->save({item_count=>$item_count}) if $Type;
					$item_count = 0;

					push @{$variable{Types}}, $Type if $Type;

					my $Paper;
					my @Papers = openprint::Paper->find( manufacturers_name=>($desc1.' '.$desc2) );
					if ( @Papers == 1 ) {
						$Paper = $Papers[0];
					} else {
					} # end if

					$Type = new openprint::Manifest_Content_Type();
					$variable{error} .= $Type->save({
						manifest_id => $$Manifest{id},
						manufacturers_name	=>	($desc1.' '.$desc2),
						type	=>	'Roll',
						( $Paper ? ( paper_id=>$Paper->id() ) : () ),
					});
					$product = $desc1.' '.$desc2;
				} # end if
				$item_count += 1;
				$Skids_by_mfg{$mfg_name} = openprint::Skid->find_one( manufacturers_id=>$mfg_name ) if ! exists $Skids_by_mfg{$mfg_name};
				my $Skid = $Skids_by_mfg{$mfg_name};
				if ( $Skid ) {
					my @SC = $Skid->Contents();
					if ( ! $$Type{paper_id} ) {
						foreach my $SC ( @SC ) {
							if ( $$SC{paper_id} ) {
								$Type->save({paper_id=>$$SC{paper_id}});
							} # end if
						} # end foreach SC
					} else {
						# Don't need to do anything, because the inequality will be shown when displaying the manifest
					} # end if
				} # end if


				my $MC = new openprint::ManifestContent();
				$variable{error} .= $MC->save({
					type_id		=>	$$Type{id},
					manifest_id	=>	$$Manifest{id},
					quantity	=>	$weight_qty,
					manufacturers_id	=>	$mfg_name,
					( $Skid ? ( skid_id=>$$Skid{id} ) : () ),
				});
			} # end while  io
			$variable{error} .= $Type->save({item_count=>$item_count}) if $Type;
			sql::end_transaction( $dbh, $ac );
		} else {
			$log->error("unknown import format: " . $upload->filename() );
		} # end if
	} # end if
} # end sub manifest_import

sub manifest_view {
	my $Manifest = $variable{Manifest} = new openprint::Manifest( $param{manifest_id} );
	if ( $param{action} eq 'Delete' ) {
		$variable{error} .= $Manifest->delete();
		$variable{ExternalRedirect} = '/employee/inventory/manifests.html' if ! $variable{error};
	} elsif ( $param{action} eq 'Undelete' ) {
		$variable{error} .= $Manifest->undelete();
		$variable{ExternalRedirect} = '/employee/inventory/manifest_view.html?manifest_id='.$Manifest->id();
	} elsif ( $param{action} eq 'Apply' ) {
		$variable{error} .= apply_Manifest( $Manifest ) if ! $variable{error};
		$variable{ExternalRedirect} = '/employee/inventory/manifest_view.html?manifest_id='.$Manifest->id();
	} elsif ( $param{action} eq 'Verify' ) {
		my $Log = new openprint::Log();
		$variable{error} .= $Log->save({
			object_type => 'openprint::Manifest',
			object_id	=> $$Manifest{id},
			action		=> 'Verify Manifest',
			user_id		=> $session{user_id},
			company_id	=> $session{company_id},
			});
		$variable{ExternalRedirect} = '/employee/inventory/manifest_view.html?manifest_id='.$Manifest->id();
	} # end if
} # end sub manifest_view

sub _stock {
}

sub allocation {
	my $Allocation = $variable{Allocation} = new openprint::PaperAllocation( $param{allocation_id} );
	if ( $param{action} eq 'Delete' ) {
		$variable{error} .= $Allocation->delete();
		if ( ! $variable{error} ) {
			$variable{ExternalRedirect} = '/employee/inventory/allocations.html';
		} # end if
	} # end if
	
} # end sub allocation

sub checks {
	_checks();
	ssi::setup_date_select( '/employee/inventory/checks.html', 'started_on_start', '' );
	ssi::setup_date_select( '/employee/inventory/checks.html', 'started_on_end', '' );
} # end sub checks

sub _checks {
	require openprint::Inventory_Check;
} # end sub _checks;

sub check {
	require openprint::Inventory_Check;
	require openprint::Inventory_Check_Entry;

	my $Check = $variable{Check} = new openprint::Inventory_Check( $param{check_id} );
	if ( $param{action} ) {
		if ( $param{action} eq 'Delete' ) {
			$variable{error} .= $Check->delete();
			$variable{ExternalRedirect} = '/employee/inventory/checks.html' if ! $variable{error};
		} elsif ( $param{action} eq 'Clear' ) {
			foreach my $ICE ( $Check->Entries() ) {
				$variable{error} .= $ICE->delete();
			}
			$variable{ExternalRedirect} = '/employee/inventory/checks.html' if ! $variable{error};
		} elsif ( $param{action} eq 'Destroy' ) {
			$variable{error} .= $Check->destroy();
			$variable{ExternalRedirect} = '/employee/inventory/checks.html' if ! $variable{error};
		} elsif ( $param{action} eq 'Download' ) {
			my $total_value = 0;
			my $total_weight = 0;
			my $count = 0;

			my @header = ('Paper ID','Type','Owner','Manufacturer','Name','Finish','Colour','Weight','Material','Group','Width','Height','Quality', 'MWeight','GSM','Skid#','RFIDTag #','Received On', 'Date Added','Last Updated', 'Location', 'In Stock (sheets)','In Stock(lbs)', 'Condition', 'Last Seen', 'Cost', 'Value', 'Allocated to Docket', 'Dockets' );
			my @data;

			my %Allocations;
			foreach my $Allocation ( openprint::PaperAllocation->find( 'skid_ids !=' => [] ) ) {
				foreach my $skid_id ( @{$Allocation->skid_ids()} ) {
					$Allocations{$skid_id} = [] if ! $Allocations{$skid_id};
					push @{$Allocations{$skid_id}}, $Allocation->docket();
				}
			}

			foreach my $ICE ( $Check->Entries() ) {
				my $Skid = $ICE->Skid();
				my $C = $ICE->SkidContent();
				$C = new openprint::SkidContent() if ! $C;
				my $Paper = $ICE->Paper();
				my $weight = 0;
				if ( $Paper->type() eq 'Roll' ) {
					$weight = $ICE->quantity();
				} elsif ( $Paper->type() eq 'Sheet' ) {
					$weight += $Paper->sheet_weight() * $ICE->quantity();
				} else {
					$log->error("Unknown stock type! " . $Paper->to_string() );
					$weight = $ICE->quantity();
				} # end if
				$total_weight += $weight;
				$count += 1;
				my $cost = $C->cost() ? $C->cost() : 45;
				my $value = $C->value() ? $C->value() : Math::Round::nearest(0.01, $cost * $ICE->quantity() /10 );
				push @data,(
						$$Paper{id},
						$Skid->type() ? $Skid->type() : 'unknown',
						new openprint::Company($Paper->owner_id())->name(),
						$Paper->manufacturer(),
						$Paper->brand() ? $Paper->brand() : 'unknown',
						$Paper->finish() ? $Paper->finish() : 'unknown',
						$Paper->colour() ? $Paper->colour() : 'unknown',
						$Paper->weight() ? $Paper->weight() : 'unknown',
						$Paper->material() ? $Paper->material() : 'unknown',
						$Paper->group(),
						$Paper->width(),
						$Paper->height(),
						$Paper->quality(),
						$Paper->mweight(),
						$Paper->gsm(),
						$ICE->skid_id(),
						$ICE->RFIDTag()->id_short(),
						$$Skid{received_on} ? ssi::format_csv_date( $$Skid{received_on} ) : ssi::format_csv_date( $$Skid{created_on} ),
						ssi::format_csv_date( $$Skid{created_on} ),
						ssi::format_csv_date( $$Skid{updated_on} ),
						( $ICE->location_id() ? $ICE->Location()->name() : $Skid->Location()->name() ),
						$Paper->type() eq 'Sheet' ? $C->quantity() : '',
						$weight,
						$C->condition(),
						ssi::format_csv_date( $$Skid{updated_on} ),#FIXME
						$cost,
						$value,
						( $Allocations{$Skid->id()} ? join(',', @{$Allocations{$Skid->id()}}) : '' ),
						join(',', $Skid->dockets() ),
						);
				$total_value += $value;
		} # end foreach ICE
		my $date = Date::Format::time2str('%Y-%m-%d %H:%M', time );
		push @data, ( 'Report generated',$date,'Count:',$count,undef,undef,undef,undef, undef,undef,undef, undef, undef, undef, undef, undef, undef, undef, undef, undef,undef, 'Total Weight (lbs):', $total_weight, undef, undef, undef, $total_value, undef, undef );
			misc::export_csv( $r, $log, \%variable, "InventoryCheck_$$Check{name}.csv", \@header, \@data );
		} elsif ( $param{action} eq 'Merge' ) {
			if ( ! $param{merge_check_id} ) {
				$variable{error} .= 'No check to merge specified.<br/>';
				return;
			}
			my $SRC_Check = new openprint::Inventory_Check( $param{merge_check_id} );
			if ( ! $$SRC_Check{id} ) {
				$variable{error} .= 'Invalid check specified.<br/>';
				return;
			} 
			foreach my $SRC_ICE ( $SRC_Check->Entries() ) {
				my $DST_ICE = $SRC_ICE->copy();
				$variable{error} .= $DST_ICE->save({ic_id=>$$Check{id}});
			}
			$variable{information} .= 'Check ' . $SRC_Check->name() . ' merged.';
		} elsif ( $param{action} eq 'Undelete' ) {
			$variable{error} .= $Check->undelete();
			$variable{ExternalRedirect} = '/employee/inventory/checks.html' if ! $variable{error};
		} elsif ( $param{action} eq 'Save' ) {
			
			if ( Date::Calc::check_date( @param{map{'started_on_'.$_}('year','month','day')} ) ) {
				$param{started_on} = join('-', @param{map{'started_on_'.$_}('year','month','day')} );
			} else {
				$variable{error} .= 'Started on date invalid.<br/>';
			}
			if ( Date::Calc::check_date( @param{map{'ended_on_'.$_}('year','month','day')} ) ) {
				$param{ended_on} = join('-', @param{map{'ended_on_'.$_}('year','month','day')} );
			} else {
				$variable{error} .= 'Ended on date invalid.<br/>';
			}

			$variable{error} .= $Check->save({
				name	=>	$param{name},
				($param{started_on} ? ( started_on	=>	$param{started_on} ) : () ),
				($param{ended_on} ? ( ended_on	=>	$param{ended_on} ) : () ),
				contains	=>	 join(',', ref $param{contains} eq 'ARRAY' ? @{$param{contains}} : $param{contains} ),
				location_id	=>	$param{location_id},
			});
			if ( ! $variable{error} ) {
				$variable{ExternalRedirect} = '/employee/inventory/check.html?check_id='.$$Check{id};
			} # end if
		} elsif ( $param{action} eq 'Delete Duplicates' ) {
			my %skid_ids;
			my %rfidtag_ids;
			my %paper_ids;

			foreach my $ICE ( openprint::Inventory_Check_Entry->find( ic_id=>$$Check{id}, order=>'skid_id,rfidtag_id' ) ) {
				if ( $$ICE{rfidtag_id} and $rfidtag_ids{$ICE->rfidtag_id()} and $skid_ids{$ICE->skid_id()} ) {
					$variable{information} .= "Deleting duplicate $$ICE{id} RFID: $$ICE{rfidtag_id} ID: " . $ICE->skid_id() . ".<br/>";
					$variable{error} .= $ICE->destroy();
				} else {
					$log->debug("No duplicate fuond for $$ICE{rfidtag_id}, previous rags: " . $rfidtag_ids{$ICE->rfidtag_id()} . ' skid_id: ' . $ICE->skid_id() . ' previous: ' . $skid_ids{$ICE->skid_id()} );
					$rfidtag_ids{$$ICE{rfidtag_id}} = $ICE;
					$skid_ids{$ICE->skid_id()} = $ICE;
				}
			}
			if ( ! $variable{information} ) {
				$variable{information} = 'No duplicates were found.<br/>';
			} else {
				$variable{error} .= $Check->save() if ! $variable{error};
			}
			$variable{ExternalRedirect} = '/employee/inventory/check.html?check_id='.$$Check{id};
		} elsif ( $param{action} eq 'Apply' or $param{action} eq 'Test' ) {

			my $ac = sql::start_transaction( $dbh );

			my @ICE = openprint::Inventory_Check_Entry->find( ic_id=>$$Check{id}, order=>'skid_id,rfidtag_id' );
			my %Skids = map { $$_{skid_id} ? ( $$_{skid_id} => $_ ) : () } @ICE;
			my %RFID = map { $$_{rfidtag_id}, $_ } @ICE;
			my @location_ids;
			if ( $Check->location_id() ) {
				@location_ids = map { $$_{id} } $Check->Location()->get_all_children();
			}
			openprint::Skid->find(id=>[ keys %Skids ] );

			my $check_time = Date::Parse::str2time( $Check->started_on() );

			foreach my $ICE ( @ICE ) {
				my $Skid = $ICE->Skid();
				if ( ! $Skid->id() ) {
					next;
				}
				my @SC = $Skid->Contents();
				if ( @SC != 1 ) {
					$variable{error} .= 'Skid ' . $Skid->link_to() . ' has more or less than 1 content. Please correct it before applying.<br/>';
					next;
				}

				my $SC = $SC[0];
				my $Paper = $SC->Paper();

				if ( $SC->checked_out() ) {
					my $PI = $SC->checked_out();
					my $pi_time = Date::Parse::str2time( $PI->updated_on() );
					if ( ! $pi_time ) {
						$log->error("Invalid pi_time");
						die;
					}

					if ( $pi_time < $check_time ) {
						if ( $ICE->quantity() and ( $ICE->quantity() != $SC->quantity() ) ) {
							if ( $SC->quantity() ) {
								$variable{information} .= 'Not adjusting adjusting quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.$ICE->quantity().'<br/>';
								next;
						
							} elsif ( $param{action} eq 'Test' ) {
								$variable{information} .= 'Would check back in ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.$ICE->quantity().'. Last changed: '.$PI->updated_on().'<br/>';
								next;
							} else {
								$variable{information} .= 'Checking back in ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' '.$ICE->quantity().'<br/>';
								$SC->save({quantity=>$ICE->quantity(), condition=>'Used', needs_verification=>1 });
								$Paper->add_inventory( $Skid, $ICE->quantity(), $Paper->units(), 'Updated from Inventory Check ' . $Check->link_to());
								next;
							}

						} elsif ( (!$SC->quantity) and $PI->delta() and ( -1*$PI->delta() != $SC->quantity() ) ) {
							if ( $param{action} eq 'Test' ) {
	$log->debug("Skid $$Skid{id} CHeck time $check_time PI time $pi_time "  );
								$variable{information} .= 'Would Adjust quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.-1*$PI->delta().'. Last changed: '.$PI->updated_on().'<br/>';
								next;
							} else {
								$variable{information} .= 'Adjusting quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.-1*$PI->delta().'<br/>';
								$SC->save({quantity=>-1*$PI->delta(), needs_verification=>1});
								$Paper->add_inventory( $Skid, -1*$PI->delta(), $Paper->units(), 'Updated from Inventory Check ' . $Check->link_to());
								next;
							}
						}
					#} else {
						#$variable{information} .= "Not checking back in " . $Paper->to_string() . ' on ' . $Skid->link_to() . ' cuz checked out after the inventory check?<br/>';
					}
				} else { # not checked out

					if ( ! $SC->quantity() and ! $ICE->quantity() ) {
						if ( my @MCs = $SC->Manifest_Contents() ) {
							my $MC = pop @MCs;
							if ( $MC->quantity() ) {
								if ( $param{action} eq 'Test' ) {
									$variable{information} .= 'Would Adjust quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.$MC->quantity().' from Manifest ' . $MC->Manifest()->link_to() . '<br/>';
								} else {
									$variable{information} .= 'Adjusting quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.$MC->quantity().' from Manifest ' . $MC->Manifest()->link_to() . '<br/>';
									$SC->save({quantity=>$MC->quantity()});
									$Paper->add_inventory( $Skid, $MC->quantity(), $Paper->units(), 'Updated from Inventory Check ' . $Check->link_to());
									next;
								}
							}
						}
					}

					if ( $SC->quantity() != int($ICE->quantity()) ) {
						if ( $param{action} eq 'Test' ) {
							$variable{information} .= 'Would adjust the quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.$ICE->quantity().'<br/>';
						} else {
							$variable{information} .= 'Adjusting quantity of ' . $Paper->to_string() . ' on ' . $Skid->link_to(). ' from ' . $SC->quantity().' to '.$ICE->quantity().'<br/>';
							$SC->save({quantity=>int($ICE->quantity()), needs_verification=>1});
							$Paper->add_inventory( $Skid, int($ICE->quantity()-$SC->quantity()), $Paper->units(), 'Updated from Inventory Check ' );
						} # endi f
					} # end if quantity needs adjusting
				} # end if checked out

				if ( $ICE->location_id() ) {
					if ( ( $Skid->location_id() != $ICE->location_id() ) and ! ( $Skid->location_id() and ! sets::isin( $Skid->location_id(), [ $ICE->location_ids() ] ) ) ) {
						if ( $param{action} eq 'Test' ) {
							$variable{information} .= 'Would adjust the location of ' . $Skid->link_to() . ' from ' . $Skid->location() . ' to ' . $ICE->location() . '<br/>';
						} else {
							$variable{information} .= 'Adjusted the location of ' . $Skid->link_to() . ' from ' . $Skid->location() . ' to ' . $ICE->location() . '<br/>';
							$Skid->save({location_id=>$$ICE{location_id}});
						} # end if
					}
				} elsif ( $$Check{location_id} and $Skid->location_id() and ! sets::isin( $Skid->location_id(), [ $Check->location_ids() ] ) ) {
						if ( $param{action} eq 'Test' ) {
							$variable{information} .= 'Would adjust the location of ' . $Skid->link_to() . ' from ' . $Skid->location() . ' to ' . $Check->Location()->name() . '<br/>';
						} else {
							$variable{information} .= 'Adjusted the location of ' . $Skid->link_to() . ' from ' . $Skid->location() . ' to ' . $Check->Location()->name() . '<br/>';
							$Skid->save({location_id=>$$ICE{location_id}});
						} # end if
				}

				last if $dbh->errstr();
			} # end foreach ICE

			my @locations = $Check->location_ids();

			foreach my $Skid ( openprint::Skid->find( 'quantity >=' => 1, 'updated_on <' => $$Check{started_on}, 
						( $Check->contains() ? ( 'type in' => [ split(',',$Check->contains())] ) : () ),
						( @location_ids ? ( location_id=>\@location_ids ) : () ),
						'inventory_check_id not'=>$Check->id(),
						) ) {
				if ( ! $$Skid{type} ) {
					if ( 0 ) {
						if ( $Skid->type() ) {
							$Skid->save();
						}
						if ( $$Skid{type} ) {
							$variable{information} .= 'Updated Skid ' . $Skid->link_to() . ' to be ' . $Skid->type() . '<br/>';
						} else {
							$variable{information} .= 'Failed to update Skid type ' . $Skid->link_to() . ' to be ' . $Skid->type() . '<br/>';
						}
					} else {
						$variable{error} .= 'Skid ' . $Skid->link_to() . ' has no type!<br/>';
					}
				} # end if ! type
				#next if it was in the inventory check
				next if $Skids{$$Skid{id}};
				if ( openprint::Inventory_Check_Entry->find_one( ic_id=>$$Check{id}, skid_id=>$$Skid{id} ) ) {
					$log->error("Didn't find skid $$Skid{id} in skid cache, but did find it in the check.");
					next;
				} 
				if ( $Skid->rfidtag_id() and openprint::Inventory_Check_Entry->find_one(ic_id=>$$Check{id}, rfidtag_id=>$Skid->rfidtag_id() ) ) {
					$log->error("Didn't find skid $$Skid{id} in skid cache, but did find it in the check by rfid.");
					next;
				} 
				$log->debug("Have skid not in check: " . $Skid->to_string() );
				if ( $param{action} eq 'Test' ) {
					$variable{information} .= 'Would check out skid ' . $Skid->link_to( $Skid->to_string() ) . ' located at ' . $Skid->location() .'<br/>';
				} else {
					$variable{information} .= 'Checked out ' . $Skid->link_to( $Skid->to_string() ) . '<br/>';
					$Skid->checkout(undef,' by Inventory Check ' . $Check->link_to() . '<br/>', 1 );
				}
				last if $dbh->errstr();
			}
			if ( $dbh->errstr() ) {
				$dbh->rollback();
			} 
			sql::end_transaction( $dbh, $ac );
			$variable{ExternalRedirect} = '/employee/inventory/check.html?check_id='.$$Check{id};

		} elsif ( $param{action} eq 'Import' ) {
			if ( ! $$Check{id} ) {
				$variable{error} .= 'No inventory check selected.<br/>';
				return;
			}
			if ( my $upload = $r->upload('import') ) {
				my %Locations = map { $$_{name}, $_ } openprint::Location->find();
				my @ICE = openprint::Inventory_Check_Entry->find( ic_id=>$$Check{id}, order=>'skid_id,rfidtag_id' );
				my %Skids = map { $$_{skid_id} ? ( $$_{skid_id} => $_ ) : () } @ICE;
				my %RFID = map { $$_{rfidtag_id}, $_ } @ICE;


				require Text::CSV_XS;
				my $csv = Text::CSV_XS->new();
				my $io =$upload->io();
				my $row = 1;
				while ( my $line = <$io> ) {
					my $status = $csv->parse($line);        # parse a CSV string into fields
					my ( $id, $rfid, $quantity, $dimension1, $dimension2, $notes, $location ) = $csv->fields();
$log->debug("Got $id, $rfid, $quantity, $dimension1, $dimension2, $notes, $location");
					$id =~ s/\D//g;
					if ( ! ( $id or $rfid ) ) {
						$log->debug("Line $line rejected due to no id or rfid");
						next;
					} # end if

					if ( $rfid =~ /R(\d+)/ ) {
						$rfid = $1;
					}

					if ( $rfid ) {
						$rfid = sprintf('2%.14d', $rfid );
						my $RFID = openprint::RFIDTag::from_id( $rfid );
						if ( ! $RFID ) {
							$log->debug("Unable to find tag from $rfid");
							$variable{error} .= "Unable to find tag from $rfid on row $row<br/>";
						} else {
							$log->debug("Found a more precise rfid for $rfid = $$RFID{id}");
							$rfid = $RFID->id();
						}
					}

					if ( $location and ( $location =~ /^(\w\w)(\d\d)$/ ) ) {
						$location = $1.$2.($2-1);
						if ( ! $Locations{$location} ) {
							$location = $1.($2+1).$2;
						}
					}
					if ( $location and ! $Locations{$location} ) {
						$variable{error} .= "Location $location for $id $rfid not in system on row $row.<br/>";	
					}

					if ( $RFID{$rfid} ) {
						$variable{error} .= "Not adding $rfid on row $row because it is already in the check.<br/>"; 
						next;
					} elsif ( $id and  $Skids{$id} ) {
						$variable{error} .= "Not adding rfid:$rfid id:$id row:$row because it is already in the check.<br/>"; 
						next;
					}

					my $ICE = new openprint::Inventory_Check_Entry();
					$ICE->set( {
						ic_id		=>	$Check->id(),
						( $id ? ( skid_id		=>	$id ) : () ),
						( $rfid ? ( rfidtag_id	=>	$rfid ) : () ),
						dimension1	=>	$dimension1,
						dimension2	=>	$dimension2,
						notes		=>	$notes,
						( ( $location and $Locations{$location} ) ? ( location_id	=>	$Locations{$location}->id() ) : () ),
					} );
					# Quantity can do auto-calcing, so needs to be done after other things are set
					$variable{error} .= $ICE->save( {
						quantity	=>	$quantity,
					} );
					$variable{error} .= $Check->save() if ! $variable{error};
				} # end while line = <IO>
				$variable{ExternalRedirect} = $Check->url_to();
			} # end if upload

		} elsif ( $param{action} eq 'Fudge' ) {
			my @ICE = openprint::Inventory_Check_Entry->find( ic_id=>$$Check{id}, order=>'skid_id NULLS FIRST,rfidtag_id' );
			foreach my $ICE ( @ICE ) {
				# Step 1, it is safe to add the rfid object to the db
				if ( $ICE->rfidtag_id() ) {
					my $RFID = openprint::RFIDTag->find_one( id=>$ICE->rfidtag_id() );
					if ( ! $RFID ) {
						$log->debug("Looking for rfid $$ICE{rfidtag_id} ");
						$RFID = new openprint::RFIDTag();
						if ( ( $ICE->rfidtag_id() =~ /^2[0-9]{14}$/ ) ) {
							$RFID->save({ id => $ICE->rfidtag_id() });
						} else {
# Must be a short form
$log->debug("RFID no good " . $RFID->id() );
die;
							$RFID->save({ id => sprintf( '2%.14d', $ICE->rfidtag_id() ) });
							$ICE->save({ rfidtag_id=>$$RFID{id} });
						}
					} else {
$log->debug( "Have an RFID object. " . $RFID->id() );
					}
				} else {
$log->debug( "No rfidtag" );
				}
				if ( ! $ICE->skid_id() ) {
$log->debug("No skid_id for " . $ICE->rfidtag_id() );
					my $RFIDTag;
					# Need to find the previous RFID tag and copy it's contents.
					if ( $ICE->rfidtag_id() ) {
						my $rfid = $ICE->rfidtag_id();
						
$log->debug("Looking for a previous rfidtag based on $rfid");
						while ( -- $rfid ) {
							if ( $rfid =~ /9999999/ ) {
								$log->debug("Dying cause $rfid");
								die ;
							}
							$RFIDTag = openprint::RFIDTag::from_id( $rfid, 2 );
							next if ! $RFIDTag;
							if ( ! $RFIDTag->skid_id() ) {	
								$RFIDTag = undef;
								next;
							}
							if ( ! $RFIDTag->Skid()->Contents() ) {
								$RFIDTag = undef;
								next;
							}
							
							last if $RFIDTag;
						} # end while
						if ( ! $RFIDTag ) {
							$log->debug("Couldn't find a previous rfidtag");
							die;
						} else {
							$log->debug("found a previous rfidtag");
						}
					}
					if ( ! $RFIDTag ) {
						$log->debug("No previous RFIDTag found.");
						next;
					}
					# No skid_id, need to allocate one, should be safe to allocate a new one.
					my $Skid = new openprint::Skid();
					$Skid->save({
						( $ICE->rfidtag_id() ? ( rfidtag_id => $ICE->rfidtag_id() ) : () ),
						type => 'Roll',
						received_on	=>	$RFIDTag->created_on(),
						owner_id		=>	$openprint::Owner->id(),
						created_on	=>	$RFIDTag->created_on(),
						updated_on	=>	$RFIDTag->created_on(),
						created_by_id	=>	$session{user_id},
					});
					$ICE->save({skid_id=>$Skid->id()});
				} # end if ! Skid_id

				if ( ! $$ICE{paper_id} ) {
					my $Skid = $ICE->Skid();
					my @Contents = $Skid->Contents();
					if ( @Contents == 1 ) {
$log->debug("Assigning stock from system.");
						$ICE->save({ paper_id=>$Contents[0]->paper_id() });
					} elsif ( @Contents ) {
$log->debug("Giving up on ssigning stock from system. as it has too many contents on $$Skid{id}");
						next;
					}
			
					my $RFIDTag;
					my $rfid = $ICE->rfidtag_id();
					while ( -- $rfid ) {
						if ( $rfid =~ /9999999/ ) {
							$log->debug("Dying because $rfid");
							die ;
						}
						$RFIDTag = openprint::RFIDTag::from_id( $rfid, 2 );
						next if ! $RFIDTag;
						if ( ! $RFIDTag->skid_id() ) {
							$RFIDTag = undef;
							next;
						}
						if ( ! $RFIDTag->Skid()->Contents() ) {
							$RFIDTag = undef;
							next;
						}

						last if $RFIDTag;
					} # end while

					$Skid = $RFIDTag->Skid();
					@Contents = $Skid->Contents();
					if ( @Contents == 1 ) {
$log->debug("Assigning stock from previous roll.");
						$ICE->save({ paper_id=>$Contents[0]->paper_id() });
					} elsif ( @Contents ) {
$log->debug("Giving up on ssigning stock from previous roll. as it has too many contents on $$Skid{id}");
						next;
					} else {
$log->debug("Dying because couldnt assign a paper for $$ICE{rfidtag_id}");
die;
					}
					
				}
				#sleep 1;	
			}

		} # end if actions
	} # end if param{action}

} # end sub check

sub _check_entries {
	my $Check = $variable{Check} = new openprint::Inventory_Check( $param{check_id} );
	if ( $param{action} eq 'add' ) {
		my $ICE = new openprint::Inventory_Check_Entry();
		$variable{error} .= $ICE->save( {
				ic_id		=>	$Check->id(),
				map { $param{$_} ? ( $_ => $param{$_} ) : () } ( 'skid_id','rfidtag_id','quantity','notes','location_id' ),
				} );
		$variable{error} .= $Check->save() if ! $variable{error};
	} # end if
	ssi::save_params( '/employee/inventory/check.html', ( 'has_skid' , 'has_quantity', 'has_price', 'sort', 'scanner_id', 'user_id', 'auto_refresh',) );
}
sub _check_system_contents {
	ssi::save_params( '/employee/inventory/check.html', ( ) );
	$variable{Check} = new openprint::Inventory_Check( $param{ic_id} );
}

sub _check_entry_actions {
}

sub _select_stock {
}

sub _check_lookup_item {
}

sub _manifest_type {
	$variable{Manifest} = new openprint::Manifest( $param{manifest_id} );
	if ( $param{action} ) {
		if ( $param{action} eq 'Add' ) {
			$variable{Type} = new openprint::Manifest_Content_Type();
			$variable{error} .= $variable{Type}->save({manifest_id=>$param{manifest_id}});
			$variable{type_id} = $variable{Type}->id();
		} elsif ( $param{action} eq 'remove' ) {
			my $Type = openprint::Manifest_Content_Type->find(id=>$param{manifest_content_type_id});
			if ( $Type ) {
				$variable{error} .= $Type->delete();
			} else {
				$variable{error} .= 'Manifest Content not found.<br/>';
			}
		} elsif ( $param{action} eq 'confirm_po_content' ) {
			my $Manifest_Content_Type = openprint::Manifest_Content_Type->find_one(id=>$param{manifest_content_type_id});
			if ( $Manifest_Content_Type ) {
				$variable{error} .= $Manifest_Content_Type->save({po_content_id=>$param{po_content_id}});
				my $POC = $Manifest_Content_Type->PurchaseOrder_Content();
				(new openprint::Log())->save({
						Object=>$Manifest_Content_Type->Manifest(),
						action=>'Edit',
						note=>'Confirm PO Content '.$POC->item(),
						});

			} else {
				$variable{error} .= "Manifest Content Type not found for id=.$param{manifest_content_type_id}<br/>";
			}
		} elsif ( $param{action} eq 'unconfirm_po_content' ) {
			my $Manifest_Content_Type = openprint::Manifest_Content_Type->find_one(id=>$param{manifest_content_type_id});
			if ( $Manifest_Content_Type ) {
				my $POC = $Manifest_Content_Type->PurchaseOrder_Content();
				$variable{error} .= $Manifest_Content_Type->save({po_content_id=>undef});
				(new openprint::Log())->save({
						Object=>$Manifest_Content_Type->Manifest(),
						action=>'Edit',
						note=>'Unconfirm PO Content '.$POC->item(),
						});
			} else {
				$variable{error} .= "Manifest Content Type not found for id=.$param{manifest_content_type_id}<br/>";
			}
		} # end if
	}
} # end sub _manifest_type
1;
__END__
