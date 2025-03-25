use strict;
package openprint::Project_Service;
our @ISA = qw(openprint::Object);

require openprint;
require openprint::Project;
require openprint::User;
require openprint::ServiceType;
require openprint::Project_Service_Operator;

use vars qw( $debug %fields %find_fields %transforms %defaults $table %serial @identified_by );

$debug = 0;
%fields = (
	service_id			=>	'lngserviceindex',
	project_id			=>	'lngprojectindex',
	operator_id			=>	'operator_id',
	operator_ids		=>	undef,
	status					=>	'strstatus',
	servicetype_id	=>	'servicetype_id',
	service_type		=>	undef,
	created_on			=>	'dtmlastmodified',
);
%find_fields = (
	category				=>	'(SELECT ServiceType_Categories.name FROM ServiceType_Categories,'.$openprint::ServiceType::table.' WHERE ServiceType_Categories.id='.$openprint::ServiceType::table.'.category_id AND '.$openprint::ServiceType::table.'.id=servicetype_id)',
	servicetype			=>	'(SELECT '.$openprint::ServiceType::fields{name}.' FROM '.$openprint::ServiceType::table.' WHERE '.$openprint::ServiceType::table.'.'.$openrpint::ServiceType::fields{id}.'=servicetype_id)',
);
%transforms = (
	
);
%defaults = (
	service_id	=>	undef,
	#operator_ids	=>	[],
	created_on	=>	q`'NOW()'`,
);
$table = 'tbl_project_contents';
%serial = ( service_id=>'ContentsServiceIndex_seq' );
@identified_by = ( 'project_id', 'service_id' );

sub Project {
	return new openprint::Project( $_[0]{project_id} );
} # end sub Project

sub operator_id {
	my ( $caller, undef, $line ) = caller;
	$openprint::log->debug("deprecated call to Project_Service::operator_id FROM $caller:$line");
	return $_[0]{operator_id};
}
sub Operator {
	my ( $caller, undef, $line ) = caller;
	$openprint::log->debug("deprecated call to Project_Service::Operator FROM $caller:$line");
	return new openprint::User( $_[0]{operator_id} );
} # end sub Operator

sub Operators {
	if ( ! $_[0]{Operators} ) {
		$_[0]{Operators} = [ openprint::Project_Service_Operator->find(service_id=>$_[0]{service_id}) ];
	}
	return @{$_[0]{Operators}};
}
sub operator_ids {
	if ( ! $_[0]{operator_ids} ) {
		 $_[0]{operator_ids} = [ map { $$_{user_id} } $_[0]->Operators() ];
	}
	return $_[0]{operator_ids};
}

sub specs {
	if ( ! $_[0]{specs} ) {
		if ( $_[0]{service_id} ) {
			$_[0]{specs} = openprint::service::get_specs_ref( $_[0]->Project(), $_[0]{service_id} );
		} else {
			$_[0]{specs} = {};
		} # end if
	} # end if
	return $_[0]{specs};
} # end sub specs

sub ServiceType {
	return new openprint::ServiceType( $_[0]{servicetype_id} );
} # end sub ServiceType

sub service_type {
	if ( @_ > 1 ) {
		$_[0]{service_type} = $_[1];
	} # end if
	if ( ! $_[0]{service_type} ) {
		$_[0]{service_type} = $_[0]->ServiceType()->type();
	} # end if
	return $_[0]{service_type};
} # end sub service_type

sub Equipment {
	my ( $self, $qty_index, @pertains ) = @_;

	my @Equipment;
	my $Project = $self->Project();

	if ( ! $qty_index ) { 
# Want ordered quantity
		$qty_index = $Project->ordered_quantity_index();
	} # end if

	my $specs = $self->specs();
	my $ServiceType = $self->ServiceType();

	if ( $ServiceType->name() eq 'Cutting' ) {
		my @equipment_ids;
		foreach my $s_id ( @pertains ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $s_id );
			my $form = $$sig_specs{SignatureIndex};

			if ( $$specs{"ddmEquipment-$form-$qty_index"} ) {
				push @equipment_ids, $$specs{"ddmEquipment-$form-$qty_index"};
			}
			if ( $$specs{"FoldingEquipment-$form-$qty_index"} ) {
				push @equipment_ids, $$specs{"FoldingEquipment-$form-$qty_index"};
			}
			# Don't do stock cut equipment
		} # end foreach s_id

		@Equipment = openprint::Equipment->find(
				id	=>	[ sets::union( @equipment_ids ) ],
				useinscheduling	=>1,
				) if @equipment_ids;

	} elsif ( $ServiceType->name() eq 'Folding' ) {
		@Equipment = openprint::Equipment->find(
				useinscheduling	=>	1,
				Specifications		=>	{'Folding Capable'=>'Y'},
				);
		} elsif ( $ServiceType->name() eq 'Stitching' ) {
			if ( $$specs{'ddmEquipment'.$qty_index} ) {
				@Equipment = openprint::Equipment->find(
						useinscheduling =>	1,
						id	=>	$$specs{'ddmEquipment'.$qty_index},
						);
			}
			if ( !@Equipment ) {
				@Equipment = openprint::Equipment->find(
						useinscheduling =>	1,
						Specifications		=>	{'Stitching Capable'=>'Y'},
						);
			} # end if
		} elsif ( ( $ServiceType->name() eq '' ) or $ServiceType->name() eq 'Signature' ) {
			@Equipment = openprint::Equipment->find( strid=>$$specs{UsePress} );
		} # end if

	#} # end if $$self{Equipment}
	return @Equipment;
} # end sub Equipment

sub runtime {
	my ( $self, $Equipment, $impressions, $speed, $pertains_to ) = @_;

	my $Project = $self->Project();
	my $qty_index = $Project->ordered_quantity_index();
	my $specs = $self->specs();
#$log->debug("Project Service runtime $$specs{ServiceType}");
	if ( $$specs{ProjectType} or ( $$specs{ServiceType} eq 'Signature' ) ) {
		my $time = openprint::Estimating::Printing::runtime( $Project, $specs, $Equipment, $impressions, $speed );
		return $$time{Total} if $time;
		return 0;
	} elsif ( $$specs{ServiceType} eq 'Cutting' ) {
		return openprint::Estimating::Cutting::runtime( $Project, $self, $Equipment, $qty_index, $impressions, $speed, $pertains_to );
	} elsif ( $$specs{ServiceType} eq 'Folding' ) {
		return openprint::Estimating::Folding::runtime( $Project, $self, $Equipment, $qty_index, $impressions, $speed, $pertains_to );
	} elsif ( $$specs{ServiceType} eq 'Drilling' ) {
		return openprint::Estimating::Drilling::runtime( $Project->id(), $$self{service_id}, $specs, $qty_index );
	} elsif ( sets::isin( $$specs{ServiceType}, 'SaddleStitching','LoopStitching' ) ) {
		return openprint::Estimating::Stitching::runtime( $Project, $self, $Equipment, $qty_index, $speed );
	} # end if

} # end sub get_runtime

sub delete {
	my ( $self ) = @_;

	if ( ! $$self{project_id} ) {
		$openprint::log->error("Attempt to delete a Project Service with no project.");
		return '';
	} # end if

  require openprint::ScheduledJob;
	# Lock all schedule
	openprint::ScheduledJob->lock();
	foreach my $Job ( openprint::ScheduledJob->find( project_id=>$$self{project_id}, 'service_id any'=>$$self{service_id} ) ) {
		$Job->save( { 
				service_id => [ sets::exclude( [ $$self{service_id} ], $Job->service_id() ) ],
				pertains_id => [ sets::exclude( [ $$self{service_id} ], $Job->pertains_id() ) ],
				} );
	} # end foreach Job
	foreach my $Job ( openprint::ScheduledJob->find( project_id=>$$self{project_id}, 'pertains_id any'=>$$self{service_id} ) ) {
		$Job->save( {
				pertains_id => [ sets::exclude( [ $$self{service_id} ], $Job->pertains_id() ) ],
				} );
	} # end foreach Job
	openprint::ScheduledJob->unlock();

	my $Project = $self->Project();
	$Project->lock();
	my $specs = $self->specs();
	sql::execute( undef, $openprint::dbh, q{DELETE FROM tbl_Service_Specifications WHERE lngProjectIndex=? AND lngServiceIndex=?}, @$self{'project_id','service_id'} );
	sql::execute( undef, $openprint::dbh, q{DELETE FROM tbl_Project_Contents WHERE lngProjectIndex=? AND lngServiceIndex=?}, @$self{'project_id', 'service_id'} );
	delete $$Project{Services};
	delete $$Project{ServicesById};
	delete $$Project{signatures};
	delete $$Project{Signature};
	delete $$Project{service_types};

	$Project->unlock();

	$Project->add_to_log( @openprint::session{'company_id','user_id'},
			'Deleted service '.$self->ServiceType()->type().' '.$$specs{ServiceName}.' '.join(' $', map { $$specs{"txtPrice$_"} } $Project->quantity_indexes() ).'.');
	return '';
} # end sub delete

sub ordered_price {
	my $specs = $_[0]->specs();
	return $$specs{'txtPrice'.$_[0]->Project()->ordered_quantity_index()};
} # end sub ordered_price

sub overrides {
	my ( $self, $qty_index ) = @_;
	my $module = 'openprint::Estimating::'.$_[0]->ServiceType()->type();
  
  if ( $module eq 'openprint::Estimating::Signature' ) {
    $module = 'openprint::Estimating::Printing';
  } elsif ( $module eq 'openprint::Estimating::AdditionalSignature' ) {
    $module = 'openprint::Estimating::Printing';
  } elsif ( $module eq 'openprint::Estimating::' ) {
    $module = 'openprint::Estimating::Printing';
  }
	eval ( 'require '.$module.';' );
	if ( my $function = $module->can( 'has_overrides' ) ) {
		my $specs = $_[0]->specs();
		my @o = $function->( $self->Project(), $$self{service_id}, $specs, $qty_index );
		return @o;
	} else {
		$openprint::log->warn("No has_overrides for " . $_[0]->ServiceType()->type() );
	} # end if
	return ();
} # end sub overrides

sub summary {
	my ( $qty_index ) = @_;

	my $Project = $_[0]->Project();
	my $services = $Project->services();
	my $ServiceType = $_[0]->ServiceType( $_[0]{service_id} );
	return '' if ! $ServiceType->summary_visible();

	my $specs = $_[0]->specs;
	if ( $$specs{ServiceType} eq 'Signature' or ( $$specs{ServiceType} eq '' and ! $$specs{txtTotalPageQuantity}  ) ) {
		require openprint::Estimating::Printing;
		return openprint::Estimating::Printing::summary($Project, $_[0]{service_id}, $specs, $qty_index );
	} elsif ( sets::isin( $$specs{ServiceType}, ['ShrinkWrap','KraftWrap','Bundling','Banding','CrossBanding'] ) ) {
		require openprint::Estimating::Packaging;
		return openprint::Estimating::Packaging::summary($Project, $_[0]{service_id}, $specs, $qty_index );
	} elsif ( sets::isin( $$specs{ServiceType}, ['SaddleStitching','LoopStitching'] ) ) {
		require openprint::Estimating::Stitching;
		return openprint::Estimating::Stitching::summary($Project, $_[0]{service_id}, $specs, $qty_index );
	} else {
		my $ServiceTypeType = $ServiceType->type();
		return if ! $ServiceTypeType;

		eval('require openprint::Estimating::'.$ServiceTypeType.';' );
		$openprint::log->error("ERror requiring openprint::Estimating::$ServiceTypeType ::summary: $@)") if $@;
		my $summary = eval('openprint::Estimating::'.$ServiceTypeType.'::summary( $Project, $_[0]{service_id}, $specs, $qty_index );' );
		$openprint::log->error("ERror evalling openprint::Estimating:: $ServiceTypeType ::summary: $@)") if $@;
		return $summary;
	} # end if
	return;
} # end sub summary

sub link_to {
	my ( $self, $text ) = @_;
	return sprintf('<a href="/main/project/view.html?ProjectIndex=%1$d&amp;ServiceIndex=%2$d">%3$s</a>', $self->Project()->id(), $self->id(), ( $text ? $text : $self->ServiceType()->name() ) );
} # end sub link_to

sub status {
	if ( @_ > 1 ) {
		$_[0]{status} = $_[1];
	}
	my $servicetype = $_[0]->service_type();

	if ( $servicetype and ( ! defined $_[0]{status} ) ) {
		my $specs = $_[0]->specs();

		my $module = 'openprint/Estimating/'.$servicetype.'.pm';
		eval{
			require $module;
		};
		$openprint::log->error("ERror requiring $module ::summary: $@)") if $@;

		if ( my $function = ('openprint::Estimating::'.$servicetype)->can('status') ) {

			$_[0]{status} = $function->($_[0]->Project(), $_[0]{service_id}, $specs );
$openprint::log->debug("New status openprint::Estiamting::$servicetype $_[0]{status} ");
		} else {
			$openprint::log->debug("No function for openprint::Estiamting::$servicetype can status");
			if ( $$specs{Status} eq 'uncalculated' ) {
				$_[0]{status} = 'uncalculated';
			} elsif ( $_[0]->Project()->order_id() ) {
				$_[0]{status} = 'Ordered';
			} else {
				$_[0]{status} = 'calculated';
			}
		}
	#} else {
		#$_[0]{status} = '';
	}
	return $_[0]{status};
} # end sub status

sub name {
	my $specs = $_[0]->specs();
	return $$specs{ServiceName} ? $$specs{ServiceName} : $_[0]->ServiceType()->description();
}

sub description {
	my $specs = $_[0]->specs();
	return $$specs{txtServiceDescription} ? ' - '.$$specs{txtServiceDescription} : '';
}

1;
__END__
