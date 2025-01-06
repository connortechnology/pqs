use strict;
use warnings;
package openprint::SkidContent;
our @ISA = qw(openprint::Object);

use vars qw( $debug %fields %find_fields %transforms %defaults $table $serial );

$debug = 0;

%fields = (
	id				=>	'id',
	skid_id			=>	'skid_id',
	paper_id		=>	'paper_id',
	quantity		=>	'quantity',
	purpose_id		=>	'purpose_id',
	units			=>	'units',
	condition_id	=>	'condition_id',
	needs_verification	=>	'needs_verification',
);
%find_fields = (
# FIXME
	allocated	=>	'(SELECT SUM(quantity) FROM Paper_Allocations WHERE Paper_Allocations.skid_id=Skid_Contents.skid_id AND paper_allocations.paper_id=Skid_Contents.paper_id)',
	deleted		=>	'(SELECT deleted FROM skids where skids.id=skid_id)',
	condition	=>	'(SELECT name FROM InventoryConditions WHERE id=skid_contents.condition_id)',
	location	=>	'(SELECT name from Locations WHERE id=(SELECT location_id FROM skids where skids.id=skid_id))',
	type		=>	'(SELECT type FROM Skids WHERE skids.id=skid_id)',
);
%defaults = (
	paper_id		=>	undef,
	quantity		=>	undef,
	purpose_id		=>	undef,
	condition_id	=>	undef,
	needs_verification	=>	0,
);
%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
);
$table = 'Skid_Contents';
$serial = 'skid_contents_id_seq';

sub units {
	$_[0]{units} = $_[1] if @_ > 1;

	if ( ! $_[0]{units} ) {
		$_[0]{units} = $_[0]->Paper()->units();
	}
	return $_[0]{units};
}

sub purpose {
	return $_[0]->Purpose()->name();
} # end sub purpose

sub Purpose {
	require openprint::StockPurpose;
	return new openprint::StockPurpose( $_[0]{purpose_id} );
} # end sub Purpose

sub Paper {
	if ( ! $_[0]{Paper} ) {
		$_[0]{Paper} = new openprint::Paper( $_[0]{paper_id} );
	} # end if
	return $_[0]{Paper};
} # end sub Paper

sub Skid {
	if ( ! $_[0]{Skid} ) {
		$_[0]{Skid} = new openprint::Skid( $_[0]{skid_id} );
	} # end if
	return $_[0]{Skid};
} # end sub Skid

sub delete {
	my $self = $_[0];
	my $error = $self->SUPER::delete();
	if ( !$error ) {
		$self->Skid()->Contents(undef);
		$self->Paper()->save() if $$self{paper_id};
	} # end if
} # end sub delete

sub allocateable {
	if ( ! exists $_[0]{allocateable} ) {
		$_[0]{allocateable} = $_[0]->quantity() - $_[0]->allocated();
		$_[0]{allocateable} = 0 if $_[0]{allocateable} < 0;
	} # end if
	return $_[0]{allocateable};
} # end sub allocateable

sub allocated {
	my $PA = openprint::PaperAllocation->find_one( paper_id=>$_[0]{paper_id},'skid_ids any'=>$_[0]{skid_id});
	return $PA->quantity() if $PA;
	return 0;
} # end sub allocated

sub condition {
    my ( $self, $condition ) = @_;

	require openprint::InventoryCondition;
    if ( defined $condition ) {
		$condition = openprint::InventoryCondition->transform('name', $condition );
		my $Condition = openprint::InventoryCondition->find_one('name lc'=>$condition);
		if ( ! $Condition ) {
			$Condition = new openprint::InventoryCondition();
			$Condition->save({'name'=>$condition});
		} # end if
        @$self{'condition_id','condition'} = @$Condition{'id','name'};
    } elsif ( $$self{condition_id} and ! $$self{condition} ) {
        $$self{condition} = new openprint::InventoryCondition( $$self{condition_id} )->name();
    } # end if
    return $$self{condition};
} # end sub condition

sub Condition {
	require openprint::InventoryCondition;
	return new openprint::InventoryCondition( $_[0]{condition_id} );
} # end sub Condition

sub Cost {
	my $self = $_[0];
	if ( ! exists $$self{Cost} ) {
		foreach my $MC ( $_[0]->Manifest_Contents() ) {
			my $Type = $MC->Type();
			if ( $Type->cost() ) {
				my $Currency = $Type->Currency();
				$$self{Cost} = {
					cost				=>	$$Type{cost},
					price				=>	$$Type{cost},
					units				=>	$Type->cost_units(),
					( $Currency ? (
					currency_id	=>	$$Currency{id},
					Currency		=>	$Currency,
					) : () )
				};
			} else {
				my $POC = $Type->PurchaseOrder_Content();
				if ( ( ! $POC ) and $$Type{docket} ) {
					# Look again without a docket
					$POC = $Type->PurchaseOrder_Content({ ignore_docket=>1 });
				}
				if ( ! $POC ) {
					$POC = $Type->PurchaseOrder_Content({ ignore_docket=>1, ignore_fsc=>1 });	
				}
				next if ! $POC;
				$$self{Cost} = $POC->Cost();
			} # end if
			last if $$self{Cost};
		} # end foreach MC
	} # end if ! exists cost
	return $$self{Cost};
}
# Looks to find a PO matching this stock and pulls the value from it.
# SKids can have multiple manifests, but only one PO
sub cost {
	my $Cost = $_[0]->Cost();
	if ( $Cost ) {
		openprint::Currency::convert( $Cost );
		return $$Cost{cost};
	}
	return;
} # end sub cost

# Looks to find a PO matching this stock and pulls the value from it.
sub value {
	my $self = $_[0];
	if ( ! exists $$self{value} ) {
		if ( $$self{quantity} ) {
			my $Cost = $_[0]->Cost();
			if ( $Cost ) {
				openprint::Currency::convert( $Cost );
				$openprint::log->debug("cost for $$self{skid_id} $$Cost{units} $$Cost{cost}") if $debug;
				if ( (!$$Cost{units}) or ($$Cost{units} eq '/100lbs' or $$Cost{units} eq '/100lb' or $$Cost{units} eq '/cwt') ) {
					if ( ! defined $$Cost{cost} ) {
						$openprint::log->error("Undefined cost in POC for skid $$self{skid_id}");
					}
					$$self{value} = $$self{quantity} * $$Cost{cost} / 100;
				} else {
					$$self{value} = $$self{quantity} * $$Cost{cost};
				} # end if
			} else {
				$openprint::log->debug("No cost for $$self{skid_id}") if $debug;
			} # end Cost
		} else {
			$$self{value} = 0;
		}
	} # end if ! exists value
	return $$self{value} if $$self{value};
	return;
} # end sub value

sub Manifest_Contents {
	if ( ! $_[0]{ManifestContents} ) {
		require openprint::ManifestContent;
		$_[0]{ManifestContents} = [ openprint::ManifestContent->find( skid_id=>$_[0]{skid_id}, order=>'id' ) ];
	}
	return @{$_[0]{ManifestContents}};
}

sub checked_out {
	if ( ! exists $_[0]{checked_out} ) {
		$_[0]{checked_out} = openprint::PaperInventory->find_one( skid_id=>$_[0]{skid_id}, paper_id=>$_[0]{paper_id}, 'comment like'=>'Checked out%', order=>'updated_on desc' ); 
	} 
	return $_[0]{checked_out};
} # end sub checked_out

sub to_string {
	return sprintf('%s%s of %s', ( $_[0]{quantity} ? Number::Format::format_number( $_[0]{quantity} ) : 'unknown'), $_[0]->units(), $_[0]->Paper()->to_string() );
}

1;
__END__
