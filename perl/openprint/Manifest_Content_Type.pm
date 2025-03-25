use strict;
package openprint::Manifest_Content_Type;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

require openprint::Manifest;
require Math::Round;

$debug = 1;

$table = 'manifest_content_types';
$serial = 'manifest_content_types_id_seq';

%fields = (
	id						=>	'id',
	cost					=>	'cost',
	cost_units		=>	'cost_units',
	docket				=>	'docket',
	po_id					=>	'po_id',
	po_content_id	=>	'po_content_id',
	manifest_id		=>	'manifest_id',
	paper_id			=>	'paper_id',
	supplier_invoice	=>	'supplier_invoice',
	item_count		=>	'item_count',
	type					=>	'type',
	manufacturers_name	=>	'manufacturers_name',
	condition_id	=>	'condition_id',
);
%find_fields = (
	total_quantity	=>	'(SELECT SUM(quantity) FROM manifestcontents WHERE manifestcontents.manifest_id=manifest_content_types.manifest_id and type_id=manifest_content_types.id)',
	skid_id					=>	'(SELECT skid_id FROM manifestcontents WHERE manifestcontents.manifest_id=manifest_content_types.manifest_id and type_id=manifest_content_types.id)',
);

%transforms = (
	paper_id			=> [ 's/\D//g' ],
	po_id					=> [ 's/\D//g' ],
	po_content_id	=> [ 's/\D//g' ],
	item_count		=> [ 's/\D//g' ],
	docket				=> [ 's/\D//g' ],
	cost					=> [ 's/[^\d\.]//g' ],
	type					=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	cost					=>	undef,
	docket				=>	undef,
	po_id					=>	undef,
	po_content_id	=>	undef,
	paper_id			=>	undef,
	type					=>	undef,
	item_count		=>	undef,
	manufacturers_name	=>	undef,
	condition_id	=>	undef,
);

sub Paper {
	require openprint::Paper;
	return new openprint::Paper( $_[0]{paper_id} );
} # end sub Paper

sub Manifest {
	return new openprint::Manifest( $_[0]{manifest_id} );
} # end sub Manifest

sub PurchaseOrder {
	return new openprint::PurchaseOrder( $_[0]{po_id} );
} # end sub PurchaseOrder

sub PurchaseOrder_Content {
	my $options = @_ > 1 ? $_[1] : {};

	if ( ! exists $_[0]{PurchaseOrder_Content} ) {
		require openprint::PurchaseOrder_Content;
		if ( $_[0]{po_content_id} ) {
			$_[0]{PurchaseOrder_Content} = new openprint::PurchaseOrder_Content($_[0]{po_content_id});
		} elsif ( $_[0]{po_id} ) {
			my $PO = new openprint::PurchaseOrder($_[0]{po_id});
			my $Paper = $_[0]->Paper();
			$openprint::log->debug('Paper desc: ' . $Paper->to_string()) if $debug;
			foreach my $POC ( $PO->Contents() ) {
				$openprint::log->debug('POC desc: '.$POC->to_string()) if $debug;
				if ( $POC->type() ne $Paper->type().' Stock' ) {
					$openprint::log->debug("not the right type POC: $$POC{type} != $$Paper{type} Stock") if $debug;
					next;
				} # end if
				if ( !$$options{ignore_docket} ) {
					if ( $POC->docket() and $_[0]{docket} ) {
						my $found = 0;
						foreach my $po_docket ( split(/[\/,]/, $POC->transform(docket=>$POC->docket()) ) ) {
							$openprint::log->debug("Not the right docket POC? ($po_docket) !=? ($_[0]{docket})") if $debug;
							if ( $po_docket eq $_[0]{docket} ) {
							  $openprint::log->debug("found POC? ($po_docket) !=? ($_[0]{docket})") if $debug;
								$found = 1;
								last;
							}
						} # end foreach po docket
						if ( !$found ) {
							$openprint::log->debug("No docket POC found? ($$POC{docket}) !=? ($_[0]{docket})") if $debug;
							next;
						}
					}
				}
				if ( $POC->item() =~ /Cover/i ) {
					if ( !$Paper->is_cover() ) {
						$openprint::log->debug("PO is cover, paper is not" ) if $debug;
						next;
					}
				} else {
					if ( $Paper->is_cover() ) {
						$openprint::log->debug("PO is not cover, paper is" ) if $debug;
						next;
					}
				}
				my ( $weight ) = $POC->item() =~ /(\d+)\w*lb/i;
				if ( $weight ) {
					$weight = Math::Round::nearest(1,$weight*2);
					#$openprint::log->debug("Looking for $weight basis_weight") if $debug;
					if ( $Paper->basis_mweight() ) {
						my $basis_weight = Math::Round::nearest(1,$Paper->basis_mweight());
						if ( $weight != $basis_weight ) {
							$openprint::log->debug("Wrong weight: 2*$weight != " . $basis_weight ) if $debug;
							next;
						} else {
							$openprint::log->debug("Right weight: $weight == " . $basis_weight ) if $debug;
						} 
					} else {
						my $paper_weight;
						if ( ( $paper_weight ) = $Paper->weight() =~ /(\d+)lb/i ) {
							if ( $weight != $paper_weight ) {
								$openprint::log->debug("Wrong weight: 2*$weight != " . $paper_weight ) if $debug;
								next;
							} else {
								$openprint::log->debug("Right weight: $weight == " . $paper_weight ) if $debug;
							}	
						}
						$openprint::log->debug("Indeterminate weight: $weight == " . $paper_weight ) if $debug;
					}
				} # end if

				my ( $caliper ) = ( $POC->item() =~ /([\.\d]+)PT/i );
				if ( $caliper ) {
					if ( $Paper->weight() =~ /([\.\d]+)PT/i ) {
						if ( $1 != $caliper ) {
							$openprint::log->debug("Caliper doesn't match $caliper != $1") if $debug;
							next;
						} # end if
					} elsif ( $Paper->calliper() and ( int($Paper->calliper()*1000) != $caliper ) ) {
						$openprint::log->debug("Caliper doesn't match $caliper != $$Paper{calliper}") if $debug;
						next;
					}
				}

				my ( $width ) = $POC->item() =~ /([\.\d]+)in/i;
				if ( $width ) {
					if ( $Paper->width() and ( $Paper->width() != $width ) ) {
						$openprint::log->debug("Wrong width: $width != " . $Paper->width() ) if $debug;
						next;
					} else {
						$openprint::log->debug("Right width: $width == " . $Paper->width() ) if $debug;
					} # end if
				} else {
					my ( $width, $height ) = $POC->item() =~ /([\d\.]+)x([\d\.]+)/i;
					if ( $width ) {
						if ( $Paper->width() and ( $Paper->width() != $width ) ) {
							$openprint::log->debug("Wrong width: $width != " . $Paper->width() ) if $debug;
							next;
						} else {
							$openprint::log->debug("Right width: $width == " . $Paper->width() ) if $debug;
						} # end if
					}
				} # end if
				if ( ! $$options{ignore_fsc} ) {
					if ( $Paper->fsc_code() and ( $POC->item() !~ /FSC/ ) ) {
						$openprint::log->debug("FSC Mismatch ") if $debug;
						next;
					} elsif ( (!$Paper->fsc_code()) and $POC->item() =~ /FSC/ ) {
						$openprint::log->debug("FSC Mismatch") if $debug;
						next;
					} # end if
				} # end if
				$openprint::log->debug('Matched '.($$POC{item}?$$POC{item}:'').' => '.$Paper->to_string()) if $debug;
				$_[0]{PurchaseOrder_Content} = $POC;
				last;
			} # end foreach POC
			#$_[0]{PurchaseOrder_Content} = new openprint::PurchaseOrder_Content() if ! $_[0]{PurchaseOrder_Content};
		} # end if if ( ( ! $_[0]{po_content_id} ) and ( $_[0]{po_id} ) )
	} # end if ! exists $_[0]{PurchaseOrder_Content}
	return $_[0]{PurchaseOrder_Content}; 
} # end sub PurchaseOrder_Content

sub match_Stock {
	my ( $self, $Stock ) = @_;

	my $TypeStock = $self->Paper();
$openprint::log->debug("Comparing " . $Stock->to_string());
$openprint::log->debug("to " . $TypeStock->to_string());

	if ( $$self{paper_id} == $$Stock{id} ) {
		$openprint::log->debug("Matched paper_id $$self{paper_id} == $$Stock{id}");
		return 1;
	}
	if ( $$self{type} ne $$Stock{type} ) {
		$openprint::log->debug("not the right type POC: $$self{type} != $$Stock{type} Stock") if $debug;
		return 0;
	} # end if

	if ( $TypeStock->width() != $Stock->width() ) {
		$openprint::log->debug("not the right width  $$TypeStock{width} != $$Stock{width} Stock") if $debug;
		return 0;
	}
	if ( $$Stock{type} eq 'Sheet' and ( $TypeStock->height() != $Stock->height() ) ) {
		$openprint::log->debug("not the right height  $$TypeStock{height} != $$Stock{height} Stock") if $debug;
		return 0;
	}

	my ( $weight ) = $TypeStock->weight() =~ /(\d+)\w*lb/i;
	if ( $weight ) {
		$weight = Math::Round::nearest(1,$weight*2);
#$openprint::log->debug("Looking for $weight basis_weight") if $debug;
		if ( $Stock->basis_mweight() ) {
			my $basis_weight = Math::Round::nearest(1,$Stock->basis_mweight());
			if ( $weight != $basis_weight ) {
				$openprint::log->debug("Wrong weight: 2*$weight != " . $basis_weight ) if $debug;
				return 0;
			} else {
				$openprint::log->debug("Right weight: $weight == " . $basis_weight ) if $debug;
			}
		} else {
			my $paper_weight;
			if ( ( $paper_weight ) = $Stock->weight() =~ /(\d+)lb/i ) {
				if ( $weight != $paper_weight ) {
					$openprint::log->debug("Wrong weight: 2*$weight != " . $paper_weight ) if $debug;
					return 0;
				} else {
					$openprint::log->debug("Right weight: $weight == " . $paper_weight ) if $debug;
				}
			}
			$openprint::log->debug("Indeterminate weight: $weight == " . $paper_weight ) if $debug;
		}
	} # end if weight

	my ( $caliper ) = $TypeStock->weight() =~ /(\d+)PT/i;
	if ( $caliper ) {
		if ( $Stock->weight() =~ /(\d+PT)/i ) {
			if ( $1 != $caliper ) {
				$openprint::log->debug("Caliper doesn't match $caliper != $1") if $debug;
				return 0;
			} # end if
		} elsif ( $Stock->calliper() and ( $Stock->calliper() != $caliper ) ) {
			$openprint::log->debug("Caliper doesn't match $caliper != $$Stock{calliper}") if $debug;
			return 0;
		}
	} # end if caliper

	return 1;

} # end sub match_Stock

sub type {
	if ( @_ > 1 ) {
		$_[0]{type} = $_[1];
	} # end if
	if ( ! $_[0]{type} ) {
		if ( $_[0]{paper_id} ) {
			$_[0]{type} = $_[0]->Paper()->type();
		} # end if
	} # end if
	return $_[0]{type};
} # end sub type

sub Contents {
	my ( $self, %params ) = @_;
	if ( %params ) {
		if ( $$self{id} ) {
			return openprint::ManifestContent->find( manifest_id=>$$self{manifest_id}, type_id=>$$self{id}, %params );
		} # end if
	} # end if
	if ( ! $$self{Contents} ) {
		if ( $$self{id} ) {
			@{$$self{Contents}} = openprint::ManifestContent->find( manifest_id=>$$self{manifest_id}, type_id=>$$self{id} );
		} # end if
	} # end if
	return @{$$self{Contents}} if $$self{Contents};
	return;
} # end sub Contents

sub condition_id {
	if ( @_ > 1 ) {
		$_[0]{condition_id} = $_[1];
	} # en dif
	if ( ! $_[0]{condition_id} ) {
		require openprint::InventoryCondition;
		my $New = openprint::InventoryCondition->find_one(name=>'new');
		$_[0]{condition_id} = $New->id() if $New;
	} # end if
	return $_[0]{condition_id};
} # end sub condition_id

sub Condition {
	require openprint::InventoryCondition;
	return new openprint::InventoryCondition($_[0]{condition_id});
} # end sub Condition

sub Order {
	if ( ( ! $_[0]{Order} ) and $_[0]{docket} ) {
		$_[0]{Order} = openprint::Order->find_one( docket=>$_[0]{docket} );
	} # end if
	return $_[0]{Order} if $_[0]{Order};
	return new openprint::Order();
		
} # end sub Order

sub Currency {
	if ( ! $_[0]{Currency} ) {
		my $Manifest = $_[0]->Manifest();
		if ( ! $$Manifest{currency_id} ) {
# Try to guess
			my $POC = $_[0]->PurchaseOrder_Content();
			if ( $POC ) {
				$$Manifest{currency_id} = $POC->PurchaseOrder()->Currency()->id();
				$Manifest->save();
			}
		}
		$_[0]{Currency} = $Manifest->Currency();	
	}
	return $_[0]{Currency};
} # end sub Currency

sub quantity {
	if ( ! $_[0]{quantity} ) {
		$_[0]{quantity} = 0;
		foreach my $C ( $_[0]->Contents() ) {
			$_[0]{quantity} += $$C{quantity};
		}
	}
	return $_[0]{quantity};
} # end sub quantity

sub units {
	my @Contents = $_[0]->Contents();
	if ( @Contents ) {
		return $Contents[0]->units();
	}
	return 'unknown';
}

sub value {
	if ( ! $_[0]{value} ) {
		$_[0]{value} = 0;
		foreach my $C ( $_[0]->Contents() ) {
			$_[0]{value} += $C->value();
		}
	}
	return $_[0]{value};
}

sub cost_units {
	my $self = shift;
	$$self{cost_units} = shift if @_;
	if ( ! $$self{cost_units} ) {
		$$self{cost_units} = '/100lb';
	}
	return $$self{cost_units};
}

sub delete {
	my $self = shift;
	foreach my $C ( $self->Contents() ) {
		$C->delete();
	}
	$self->SUPER::delete();
}
sub check {
	my ( $T ) = @_;

	my $error = '';
	$error .= $T->Paper()->check();
	$error .= $T->PurchaseOrder_Content()->check($T->Paper()) if $$T{po_content_id};
	if ( $$T{po_id} ) {
		my $PO = openprint::PurchaseOrder->find_one(id=>$$T{po_id});
		if ( !$PO ) {
			$error .= "No purchase order found for $$T{po_id}<br/>";
		} else {
			if ( $$T{docket} and !$T->PurchaseOrder_Content() ) {
				my $docket_found = 0;
				foreach my $POC ( $PO->Contents() ) {
					if ( $POC->docket() eq $$T{docket} ) {
						$docket_found = 1;
						last;
					}
				}
				if ( !$docket_found ) {
					$error .= 'No line found in po ' . $PO->link_to().' for docket ' . $$T{docket}.'<br/>';
				}
			} # end if docket and no POC
		} # end if found po
	}
	return $error;
}

1;
__END__
