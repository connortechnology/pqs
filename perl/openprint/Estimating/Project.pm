use strict;
package openprint::Estimating::Project;

use openprint ();
use vars qw( $r $log $dbh %session );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;

use constant DEBUG => 1;

require sql;
require openprint::service;
require openprint::ServiceType;
require openprint::ProjectType;
require openprint::Project;
require openprint::Currency;
require openprint::ServiceType;
require openprint::Estimating::MultiPage;

# Projects are like Orders, in that you can have several in here, but only ONE of them may be unfinished.

my @no_outputs = (
    'txtShippingPostalCode',
    'txtHoleQty','UPSShipping','HoleDrilling',
    'Aqueous','txtTotalPageQuantity','Colours',
    'ddmStockBrand','ddmStockFinish','ddmStockColour','ddmStockWeight',
    'ddmStockBrand1','ddmStockFinish1','ddmStockColour1','ddmStockWeight1',
    'ddmStockBrand2','ddmStockFinish2','ddmStockColour2','ddmStockWeight2',
    'txtHoleSize', 
    'rdbAqueousSideOne','rdbAqueousSideTwo',
    'chkProcessColourSideOne', 'chkProcessColourSideTwo',
    'TemplateType','PrintingType','FoldType','Dimensions','Turnaround',
# Presentation Folders
    'rdbPanels','rdbPocketSize','chkPocketLeft','chkPocketRight',
    'txtQuantity1',
    'chkOverrideScoreQty',
    'h_stands','grommets',
    );

sub no_outputs {
  return @no_outputs;
} # end sub

# creates a new project, first clearing out any previous projects
sub calc {
  my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

# FIrst thing: Normalize the inputs
  $$specs{Help} = '';
  $$specs{alert} = '';
  $$specs{txtQuantity1} =~ s/\D//g;
  $$specs{txtPrice1} = '';
  $$specs{txtUnitPrice1} = '';

  $openprint::log->debug("In Project::calc");
  my $ProjectType = new openprint::ProjectType( $$specs{projecttype_id} );
  my $Project = new openprint::Project( $project_index );
  if ( $project_index and ! $$Project{id} ) {
    $log->error("Project Index was specified, but not found. $project_index");
    $Project->save();
  } else {
    $log->debug("Have project $project_index $$Project{id}");
  }
  my $services = $Project->services();
  $Project->Currency( openprint::Currency::get_current() );
  if ( $Project->type_id() != $ProjectType->id() ) {
    $Project->change_ProjectType( $ProjectType );
  } # end if

  if ( $Project->id() and ( $$specs{txtQuantity1} != $Project->quantity1() ) ) {
    foreach my $service_name ( keys %$services ) {
      foreach my $service_id ( @{$$services{$service_name}} ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $service_id, 'txtQuantity1', $$specs{txtQuantity1} );
      } # end foreach
    } # end foreach
    $Project->quantity1( $$specs{txtQuantity1} );
  } # end if

  $Project->mode( 'Simple' );
  $Project->design( 'ElectronicFile' );
  $Project->reference( $$specs{reference} );
  if ( $_ = $Project->save() ) {
    $log->error( $_ );
  } # end if

  if ( ! $$Project{id} ) {
    $$specs{alert} = 'There was an error storing the project..  Please contact us for help.';
    return $$specs{Status} = 'uncalculated';
  } # end if project_id

  $openprint::session{project_id} = $Project->id();
  $$specs{ProjectIndex} = $$Project{id};

  if ( ! $$services{''} ) {
    push @{$$services{''}}, openprint::print_project::insert_project_type( $r, $log, $dbh, $$Project{id}, $ProjectType->name() );
  } # end if

  my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
  if ( $$project_specs{ProjectType} ne $ProjectType->name() ) {
    openprint::print_project::delete_service( $Project, $$services{''}[0] );
    $$services{''}[0] = openprint::print_project::insert_project_type( $r, $log, $dbh, $$Project{id}, $ProjectType->name() );
    $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
  } # end if

  foreach my $servicetype_id ( sql::execute( $log, $dbh, q{SELECT (SELECT name FROM Service_Types WHERE id = servicetype_id ) FROM projecttype_requiredservices WHERE projecttype_id = ?}, $Project->type_id() ) ) {
    if ( ! $$services{$servicetype_id} ) {
      push @{$$services{$servicetype_id}}, $Project->add_service( $servicetype_id );
    } # end if
  } # end foreach

  if ( $$specs{Numbering} eq 'Y' ) {
    if ( ! $$services{Numbering} ) {
      push @{$$services{Numbering}}, $Project->add_service( 'Numbering' );
# Load defaults
      my $numbering_specs = openprint::service::get_specs_ref( $Project, $$services{Numbering}[0] );
      $$specs{colour} = $$numbering_specs{colour} if ! $$specs{Colour};
      $$specs{SetsOfNumbers} = $$numbering_specs{SetsOfNumbers} if ! $$specs{SetsOfNumbers};
    } # end if
    foreach my $sid ( @{$$services{Numbering}} ) {
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'colour', $$specs{colour} );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'SetsOfNumbers', $$specs{SetsOfNumbers} );
    } # end foreach
  } elsif ( $$services{Numbering} ) {
    foreach ( @{$$services{Numbering}} ) {
      openprint::print_project::delete_service( $Project, $_ );
    } # end foreach
    delete $$services{Numbering};
  } # end if
  if ( $$specs{hemmed} eq 'Y' ) {
    if ( ! $$services{Sewing} ) {
      push @{$$services{Sewing}}, $Project->add_service( 'Sewing' );
      my $sewing_specs = openprint::service::get_specs_ref( $Project, $$services{Sewing}[0] );
      @$specs{'EdgeLeft','EdgeRight','EdgeTop','EdgeBottom'} = @$sewing_specs{'EdgeLeft','EdgeRight','EdgeTop','EdgeBottom'};
    } # end if
    foreach my $sid ( @{$$services{Sewing}} ) {
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'EdgeLeft', $$specs{EdgeLeft} );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'EdgeRight', $$specs{EdgeRight} );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'EdgeTop', $$specs{EdgeTop} );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'EdgeBottom', $$specs{EdgeBottom} );
    } # end foreach
  } elsif ( $$services{Sewing} ) {
    map { openprint::print_project::delete_service( $Project, $_ ); } @{$$services{Sewing}};
    delete $$services{Sewing};
  } # end if

  if ( $$specs{grommeting} eq 'Y' ) {
    if ( ! $$services{Grommeting} ) {
      push @{$$services{Grommeting}}, $Project->add_service( 'Grommeting' );
      my $grommeting_specs = openprint::service::get_specs_ref( $Project, $$services{Grommeting}[0] );
      $$specs{grommets} = $$grommeting_specs{Quantity};
    } 
  } elsif ( $$services{Grommeting} ) {
    map { openprint::print_project::delete_service( $Project, $_ ); } @{$$services{Grommeting}};
    delete $$services{Grommeting};
  } # end if

  if ( $$specs{h_stands} eq 'Y' ) {
    if ( ! $$services{HStands} ) {
      push @{$$services{HStands}}, $Project->add_service( 'HStands' );
    } # end i
  }

  if ( ! sets::isin( $$specs{Dimensions}, [ 'Custom'] ) ) {
    if ( ! $$specs{Dimensions} ) {
      $$specs{alert} .= 'Please select the Size<br/>';

    } else {

      my ( $width, $height, $type ) = $$specs{Dimensions} =~ /([\d\.]*)x([\d\.]*)(\w*)/;
      my @args = ( $$specs{projecttype_id}, $width, $height );

      if ( $type eq 'Flat' ) {
        $_ = q{SELECT dblfinishedwidth::float, dblfinishedheight::float FROM projecttemplate WHERE projecttype_id=? AND dblFlatWidth=? AND dblFlatHeight=?};
        if ( $$specs{FoldType} ) {
          $_ .= q{ AND type=?};
          push @args, $$specs{FoldType};
        } # end if
        @$specs{'txtFinalWidth','txtFinalHeight'} = sql::execute( $log, $dbh, $_, @args );
        @$specs{'txtWidth','txtHeight'} = ($width, $height);
        if ( ! $$specs{txtFinalWidth} ) {
          if ( ( my ( $pages, $folds ) = $$specs{FoldType} =~ /^(\d+)pg(\d)Panel/ ) ) {
            $$specs{txtFinalWidth} = sprintf('%.3f', int($$specs{txtWidth} * 1000 / $folds)/1000 );
            $$specs{txtFinalHeight} = $$specs{txtHeight} / (($pages/2)/$folds);
          } elsif ( ( my ( $folds ) = $$specs{FoldType} =~ /^(\d)Panel/ ) ) {
#$folds =~ s/\D//g;
#$folds += 1;
            $$specs{txtFinalWidth} = sprintf('%.3f', int($$specs{txtWidth}*1000/$folds)/1000 );
            $$specs{txtFinalHeight} = $$specs{txtHeight};
          } # end if
        } # end if
      } else {
        $_ = q{SELECT dblFlatWidth::float, dblFlatHeight::float FROM projecttemplate WHERE projecttype_id=? AND dblFinishedWidth=? AND dblFinishedHeight=?};
        if ( $$specs{FoldType} ) {
          $_ .= q{ AND type=?};
          push @args, $$specs{FoldType};
        } # end if
        @$specs{'txtWidth','txtHeight'} = sql::execute( $log, $dbh, $_, @args );
        @$specs{'txtFinalWidth','txtFinalHeight'} = ($width, $height);
        if ( ! $$specs{txtWidth} ) {
          my $folds = $$specs{FoldType};
          $folds =~ s/\D//g;
          $folds += 1;
          $$specs{txtWidth} = $$specs{txtFinalWidth} * $folds;
          $$specs{txtHeight} = $$specs{txtFinalHeight};
        } # end if
      } # end if
      if ( $ProjectType->name() eq 'PresentationFolders' ) {
        $log->debug("Presentation folder sizes $$specs{chkPocketLeft} $$specs{chkPocketRight} ");
        $$specs{txtWidth} = $$specs{txtFinalWidth} * 2;
        my $pockets;
        if ( $$specs{chkPocketLeft} ) {
          $$specs{txtWidth} += 0.75;
          $pockets += 1;
        } # end if
        if ( $$specs{chkPocketRight} ) {
          $$specs{txtWidth} += 0.75;
          $pockets += 1;
        } # end if
        $$specs{txtHeight} = $$specs{txtFinalHeight} + $$specs{rdbPocketSize};
      } # end if
    }
  } elsif ( ( $ProjectType->name() eq 'Envelopes' ) and ( exists $$specs{ddmStockSize} ) ) {
    @$specs{'txtWidth','txtHeight'} = $$specs{ddmStockSize} =~ /^([\d\.]+)"?\s*x?\s*([\d\.]+)?"?\s*$/;
    @$specs{'txtFinalWidth','txtFinalHeight'} = @$specs{'txtWidth','txtHeight'};
  } else {
    $$specs{txtWidth} =~ s/[^\.\d]//g;
    $$specs{txtFinalWidth} =~ s/[^\.\d]//g;
    $$specs{txtHeight} =~ s/[^\.\d]//g;
    $$specs{txtFinalHeight} =~ s/[^\.\d]//g;
    if ( $$specs{spine} eq 'width' ) {
      @$specs{'txtWidth','txtHeight'} = ( $$specs{txtFinalWidth}, 2*$$specs{txtFinalHeight} );
    } # end if
  } # end if Custom

  if ( $$specs{FoldType} and ! ( $$specs{txtWidth} and $$specs{txtHeight} and $$specs{txtFinalWidth} and $$specs{txtFinalHeight} ) ) {
    $$specs{alert} .= 'No dimensions found for this fold type.';
    return $$specs{Status} = 'uncalculated';
  } # end if

  my @StockOptions = misc::trim(split (',', $openprint::config{$Project->Type()->name().'StockOptions'} ) );
  @StockOptions = misc::trim(split (',', $openprint::config{StockOptions} )) if ! @StockOptions;
  @StockOptions = ( 'Brand','Finish','Colour','Weight' ) if ! @StockOptions;

  $Project->lock();
  if ( $dbh->errstr() ) {
    $log->error( $dbh->errstr() );
    $Project->unlock();
    $$specs{alert} .= 'Database error<br/>';
    return $$specs{Status} = 'uncalculated';
  } # end if

  if ( exists $$specs{txtTotalPageQuantity} ) {
# It's a multi-page publication
    if ( ! $$specs{txtTotalPageQuantity} ) {
      $$specs{alert} .= 'Please enter the number of pages.<br/>';
      $Project->unlock();
      return $$specs{Status} = 'uncalculated';
    } # end if
    if ( $$specs{rdbCover} eq 'Different' ) {
      foreach my $option ( @StockOptions ) {
        if ( ! $$specs{'ddmStock'.$option.'1'} ) {
          $$specs{alert} .= 'Please select a cover stock ' . lc $option .'.';
          $Project->unlock();
          return $$specs{Status} = 'uncalculated';
        } # end if
      } # end foreach option
    } # end if
    foreach my $option ( @StockOptions ) {
      if ( ! $$specs{'ddmStock'.$option.'2'} ) {
        $$specs{alert} .= 'Please select an interior stock ' . lc $option .'.';
        $Project->unlock();
        return $$specs{Status} = 'uncalculated';
      } # end if
    } # end foreach option

    if ( $$specs{rdbTemplateType} eq 'SaddleStitching' and $$specs{txtTotalPageQuantity} % 4 ) {
      $$specs{alert} .= '# of pages should be a multiple of 4<br/>';
      $Project->unlock();
      return $$specs{Status} = 'uncalculated';
    } elsif ( $$specs{rdbTemplateType} eq 'PerfectBound' and $$specs{txtTotalPageQuantity} % 2 ) {
      $$specs{alert} .= '# of pages should be a multiple of 2<br/>';
      $Project->unlock();
      return $$specs{Status} = 'uncalculated';
    } # end if

# Setup the colours
    if ( $$specs{Colours} eq '4/4' ) {
      $$specs{chkBlackSideOne2} = undef;
      $$specs{chkBlackSideTwo2} = undef;
      $$specs{chkProcessColourSideOne2} = 'ProcessColour';
      $$specs{chkProcessColourSideTwo2} = 'ProcessColour';
    } elsif ( $$specs{Colours} eq '4/0' ) {
      $$specs{chkBlackSideOne2} = undef;
      $$specs{chkBlackSideTwo2} = undef;
      $$specs{chkProcessColourSideOne2} = 'ProcessColour';
      $$specs{chkProcessColourSideTwo2} = '';
    } elsif ( $$specs{Colours} eq '4/1' ) {
      $$specs{chkBlackSideOne2} = undef;
      $$specs{chkBlackSideTwo2} = 'Black';
      $$specs{chkProcessColourSideOne2} = 'ProcessColour';
      $$specs{chkProcessColourSideTwo2} = undef;
    } elsif ( $$specs{Colours} eq '1/1' ) {
      $$specs{chkBlackSideOne2} = 'Black';
      $$specs{chkBlackSideTwo2} = 'Black';
      $$specs{chkProcessColourSideOne2} = undef;
      $$specs{chkProcessColourSideTwo2} = undef;
    } elsif ( $$specs{Colours} eq '1/0' ) {
      $$specs{chkBlackSideOne2} = 'Black';
      $$specs{chkBlackSideTwo2} = undef;
      $$specs{chkProcessColourSideOne2} = undef;
      $$specs{chkProcessColourSideTwo2} = undef;
    } # end if
    my $colourindex = 1;
    if ( $$specs{SideOneCoatingType2} and ( $$specs{SideOneCoatingType2} ne 'None' ) ) {
      $$specs{'chkColourCoating'.$colourindex.'SideOne2'} = 'Y';
      $$specs{'ColourCoatingType'.$colourindex.'SideOne2'} = 'UVCoating'.$$specs{SideOneCoatingType2};
      $colourindex += 1;
    } else {
      $$specs{'chkColourCoating'.$colourindex.'SideOne2'} = '';
      $$specs{'ColourCoatingType'.$colourindex.'SideOne2'} = '';
    } # end if

    if ( $$specs{SideTwoCoatingType2} and ( $$specs{SideTwoCoatingType2} ne 'None' ) ) {
      $$specs{'chkColourCoating'.$colourindex.'SideTwo2'} = 'Y';
      $$specs{'ColourCoatingType'.$colourindex.'SideTwo2'} = 'UVCoating'.$$specs{SideTwoCoatingType2};
      $colourindex += 1;
    } else {
      $$specs{'chkColourCoating'.$colourindex.'SideTwo2'} = '';
      $$specs{'ColourCoatingType'.$colourindex.'SideTwo2'} = '';
    } # end if
    if ( $$specs{Aqueous2} and $$specs{Aqueous2} ne 'None' ) {
      $$specs{'chkColourCoating'.$colourindex.'SideOne2'} = 'Y';
      $$specs{'ColourCoatingType'.$colourindex.'SideOne2'} = $$specs{Aqueous2};
      $$specs{'chkColourCoating'.$colourindex.'SideTwo2'} = 'Y';
      $$specs{'ColourCoatingType'.$colourindex.'SideTwo2'} = $$specs{Aqueous2};
      $colourindex += 1;
    } else {
      $$specs{'chkColourCoating'.$colourindex.'SideOne2'} = '';
      $$specs{'ColourCoatingType'.$colourindex.'SideOne2'} = '';
      $$specs{'chkColourCoating'.$colourindex.'SideTwo2'} = '';
      $$specs{'ColourCoatingType'.$colourindex.'SideTwo2'} = '';
    } # end if

    if ( $$specs{rdbCover} eq 'Different' ) {
      if ( $$specs{ColoursCover} eq '4/4' ) {
        $$specs{chkBlackSideOne1} = undef;
        $$specs{chkBlackSideTwo1} = undef;
        $$specs{chkProcessColourSideOne1} = 'ProcessColour';
        $$specs{chkProcessColourSideTwo1} = 'ProcessColour';
      } elsif ( $$specs{ColoursCover} eq '4/0' ) {
        $$specs{chkBlackSideOne1} = undef;
        $$specs{chkBlackSideTwo1} = undef;
        $$specs{chkProcessColourSideOne1} = 'ProcessColour';
        $$specs{chkProcessColourSideTwo1} = undef;
      } elsif ( $$specs{ColoursCover} eq '4/1' ) {
        $$specs{chkBlackSideOne1} = undef;
        $$specs{chkBlackSideTwo1} = 'Black';
        $$specs{chkProcessColourSideOne1} = 'ProcessColour';
        $$specs{chkProcessColourSideTwo1} = undef;
      } # end if
      my $colourindex = 1;
      if ( $$specs{SideOneCoatingType1} and ( $$specs{SideOneCoatingType1} ne 'None' ) ) {
        $$specs{'chkColourCoating'.$colourindex.'SideOne1'} = 'Y';
        $$specs{'ColourCoatingType'.$colourindex.'SideOne1'} = 'UVCoating'.$$specs{SideOneCoatingType1};
        $colourindex += 1;
      } else {
        $$specs{'chkColourCoating'.$colourindex.'SideOne1'} = '';
        $$specs{'ColourCoatingType'.$colourindex.'SideOne1'} = '';
      } # end if

      if ( $$specs{SideTwoCoatingType1} and ( $$specs{SideTwoCoatingType1} ne 'None' ) ) {
        $$specs{'chkColourCoating'.$colourindex.'SideTwo1'} = 'Y';
        $$specs{'ColourCoatingType'.$colourindex.'SideTwo1'} = 'UVCoating'.$$specs{SideTwoCoatingType1};
        $colourindex += 1;
      } else {
        $$specs{'chkColourCoating'.$colourindex.'SideTwo1'} = '';
        $$specs{'ColourCoatingType'.$colourindex.'SideTwo1'} = '';
      } # end if

      if ( $$specs{Aqueous1} and $$specs{Aqueous1} ne 'None' ) {
        $$specs{'chkColourCoating'.$colourindex.'SideOne1'} = 'Y';
        $$specs{'ColourCoatingType'.$colourindex.'SideOne1'} = $$specs{Aqueous1};
        $$specs{'chkColourCoating'.$colourindex.'SideTwo1'} = 'Y';
        $$specs{'ColourCoatingType'.$colourindex.'SideTwo1'} = $$specs{Aqueous1};
        $colourindex += 1;
      } else {
        $$specs{'chkColourCoating'.$colourindex.'SideOne1'} = '';
        $$specs{'ColourCoatingType'.$colourindex.'SideOne1'} = '';
        $$specs{'chkColourCoating'.$colourindex.'SideTwo1'} = '';
        $$specs{'ColourCoatingType'.$colourindex.'SideTwo1'} = '';
      } # end if

    } # end if Cover is different
    my $variables_func = "openprint::Estimating::$$ProjectType{type}"->can( 'variables' );
    if ( $variables_func ) {
    my @variables = $variables_func->( $$Project{id}, $$services{''}[0], $project_specs, $specs );
    $log->debug("Got vars @variables");
    foreach my $spec ( @variables ) {
      if ( $$project_specs{$spec} ne $$specs{$spec} ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{''}[0], $spec, $$specs{$spec} );
      } # end if
    } # end foreach
    } else {
      $log->error("$$ProjectType{type}::variables does not exist");
    }

# Sets up the book service
    openprint::service::internal_calc( $log, $dbh, $variable, $$Project{id}, $$services{''}[0], $ProjectType->type() );
    my $func = "openprint::Estimating::$$ProjectType{type}"->can('save');
    if ( $func ) {
    $func->( $$Project{id}, $$services{''}[0], $project_specs );
    }
# The adding of signatures will be done automatically by multipage_signatures
# This will add bindery services, and a printing service
    #$$specs{Status} = openprint::print::multipage_signatures( $specs, $log, $dbh, $variable, $$Project{id}, $$services{''}[0] );
  } elsif ( $ProjectType->type() ne 'ChannelLetters' ) {
# Non-book
    my @signatures = $Project->signatures();
    if ( ! @signatures ) {
      push @signatures, $Project->add_signature( 1, undef, { txtQuantity1 => $$specs{txtQuantity1} } );	
    } # end if
    my $sig_id = $signatures[0];
    my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );

    if ( $$specs{Colours} eq '4/4' ) {
      $$specs{chkBlackSideOne} = undef;
      $$specs{chkBlackSideTwo} = undef;
      $$specs{chkProcessColourSideOne} = 'ProcessColour';
      $$specs{chkProcessColourSideTwo} = 'ProcessColour';
    } elsif ( $$specs{Colours} eq '4/0' ) {
      $$specs{chkBlackSideOne} = undef;
      $$specs{chkBlackSideTwo} = undef;
      $$specs{chkProcessColourSideOne} = 'ProcessColour';
      $$specs{chkProcessColourSideTwo} = '';
    } elsif ( $$specs{Colours} eq '4/1' ) {
      $$specs{chkBlackSideOne} = undef;
      $$specs{chkBlackSideTwo} = 'Black';
      $$specs{chkProcessColourSideOne} = 'ProcessColour';
      $$specs{chkProcessColourSideTwo} = undef;
    } elsif ( $$specs{Colours} eq '1/0' ) {
      $$specs{chkBlackSideOne} = 'Black';
      $$specs{chkBlackSideTwo} = undef;
      $$specs{chkProcessColourSideOne} = undef;
      $$specs{chkProcessColourSideTwo} = undef;
    } elsif ( $$specs{Colours} eq '1/1' ) {
      $$specs{chkBlackSideOne} = 'Black';
      $$specs{chkBlackSideTwo} = 'Black';
      $$specs{chkProcessColourSideOne} = undef;
      $$specs{chkProcessColourSideTwo} = undef;
    } # end if
    if ( 1 == ( my @Papers = openprint::Paper->find(
            ( exists $$specs{ddmStockBrand} ? ( 'brand'		=>	$$specs{ddmStockBrand} ) : () ),
            ( exists $$specs{ddmStockFinish} ? ( 'finish'	=>	$$specs{ddmStockFinish} ) : () ),
            ( exists $$specs{ddmStockWeight} ? ( 'weight'	=>	$$specs{ddmStockWeight} ) : () ),
            ( exists $$specs{ddmStockColour} ? ( 'colour'	=>	$$specs{ddmStockColour} ) : () ),
            ( exists $$specs{ddmStockSheetSize} ? ( 'size'		=>	$$specs{ddmStockSheetSize} ) : () ),
            ( exists $$specs{ddmStockSize} ? ( 'size'		=>	$$specs{ddmStockSize} ) : () ),
            ) ) ) {
      $$specs{ddmStockBrand} = $Papers[0]->name() if ! $$specs{ddmStockBrand};
      $$specs{ddmStockFinish} = $Papers[0]->finish() if ! $$specs{ddmStockFinish};
      $$specs{ddmStockWeight} = $Papers[0]->weight() if ! $$specs{ddmStockWeight};
      $$specs{ddmStockColour} = $Papers[0]->colour() if ! $$specs{ddmStockColour};
    } else {
      foreach my $option ( @StockOptions ) {
        if ( ! $$specs{'ddmStock'.$option} ) {
          $$specs{alert} .= 'Please select stock ' . lc $option .'.';
          $Project->unlock();
          return $$specs{Status} = 'uncalculated';
        } # end if
      } # end foreach option
    } # end if


    my $colourindex = 1;

    if ( 
        ( $$specs{SideOneCoatingType} and ( $$specs{SideOneCoatingType} ne 'None' ) ) or
        ( $$specs{SideTwoCoatingType} and ( $$specs{SideTwoCoatingType} ne 'None' ) ) 
       ) {
      if ( $$specs{SideOneCoatingType} and ( $$specs{SideOneCoatingType} ne 'None' ) ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideOne', 'Y' );
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideOne', 'UVCoating'.$$specs{SideOneCoatingType} );
      } # end if
      if ( $$specs{SideTwoCoatingType} and ( $$specs{SideTwoCoatingType} ne 'None' ) ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideTwo', 'Y' );
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideTwo', 'UVCoating'.$$specs{SideTwoCoatingType} );
      } # end if
      if ( ! $$services{UVCoating} ) {
        push @{$$services{UVCoating}}, $Project->add_service( 'UVCoating' );
      } # end if
      $colourindex += 1;
    } elsif ( $$services{UVCoating} ) {
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideOne', '' );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideOne', '' );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideTwo', '' );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideTwo', '' );
      foreach ( @{$$services{UVCoating}} ) {
        openprint::print_project::delete_service( $Project, $_ );
      } # end foreach
      delete $$services{UVCoating};
    } # end if

    if ( $$specs{Aqueous} and $$specs{Aqueous} ne 'None' ) {
      if ( get_colours( $specs, 'SideOne' ) ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideOne', 'Y' );
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideOne', $$specs{Aqueous} );
      } else {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideOne', '' );
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideOne', '' );
      } 
      if ( get_colours( $specs, 'SideTwo' ) ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideTwo', 'Y' );
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideTwo', $$specs{Aqueous} );
      } else {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideTwo', '' );
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideTwo', '' );
      } # end if
      if ( ! $$services{Aqueous} ) {
        push @{$$services{Aqueous}}, $Project->add_service( 'Aqueous' );
      } # end if
      $colourindex += 1;
    } else {
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideOne', '' );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideOne', '' );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'chkColourCoating'.$colourindex.'SideTwo', '' );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'ColourCoatingType'.$colourindex.'SideTwo', '' );
      foreach ( @{$$services{Aqueous}} ) {
        openprint::print_project::delete_service( $Project, $_ );
      } # end foreach
      delete $$services{Aqueous};
    } # end if

    foreach my $spec ( 'txtWidth','txtHeight','txtFinalWidth','txtFinalHeight', 'ddmStockBrand','ddmStockFinish','ddmStockColour','ddmStockWeight','txtQuantity1','chkProcessColourSideOne','chkProcessColourSideTwo','chkBlackSideOne','chkBlackSideTwo','PageQuantity', 'ddmStockSize' ) {
      if ( $$sig_specs{$spec} ne $$specs{$spec} ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, $spec, $$specs{$spec} );
      } # end if
    } # end foreach
    if ( $$specs{PrintingType} ) {
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'PrintingType1', $$specs{PrintingType} );
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'OverridePrintingType1', 'Y' );
    } else {
      openprint::service::delete_service_spec( $$Project{id}, $sig_id, 'OverridePrintingType1' );
    } # end if
    if ( $ProjectType->name() eq 'PresentationFolders' ) {
      foreach my $spec ( 'rdbPanels','rdbPocketSize','chkPocketLeft','chkPocketRight','chkPocketCenter' ) {
        if ( $$sig_specs{$spec} ne $$specs{$spec} ) {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, $spec, $$specs{$spec} );
        } # end if
      } # end foreach
    } else {
      foreach my $spec ( 'PocketSize','grommets','hemmed','pockets','EdgeLeft','EdgeRight','EdgeBottom','EdgeTop' ) {
#openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services[0], $spec, $$specs{$spec} );
        $$project_specs{$spec} = $$specs{$spec};

        if ( $$sig_specs{$spec} ne $$specs{$spec} ) {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, $spec, $$specs{$spec} );
        } # end if
      } # end foreach
      openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sig_id, 'rdbTemplateType', $$specs{FoldType} );
    } # end if

# Although this could calculate the printing, it is here only to further store and validate and auto-ppulate fields
    $sig_specs = openprint::service::internal_calc( $log, $dbh, $variable, $$Project{id}, $sig_id, 'Printing' );
    @$specs{'txtWidth','txtHeight','chkPocketCenter','alert','Status'} = @$sig_specs{'txtWidth','txtHeight','chkPocketCenter','alert','Status'};
  } else { # ChannelLetters
    eval 'require openprint::Estimating::'.$ProjectType->type();
    $log->error("Error in requiring $$ProjectType{type} $@") if $@;
    my @variables = eval('openprint::Estimating::'.$ProjectType->type().'::variables($project_index, $service_index, $project_specs, $specs)');
    $log->error("Error in requiring $$ProjectType{type} $@") if $@;
    $log->debug("Vars for $$ProjectType{type} : @variables");

    foreach my $spec ( @variables ) {
      if ( $$project_specs{$spec} ne $$specs{$spec} ) {
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{''}[0], $spec, $$specs{$spec} );
      } # end if
    } # end foreach
  } # end if printing (actually looks for txtTotalPageQut
      my $service_specs = openprint::service::internal_calc( $log, $dbh, $variable, $$Project{id}, $$services{''}[0], $ProjectType->type() );
      $$specs{Status} = $$service_specs{Status};
      $$specs{alert} .= $$service_specs{alert};

      if ( ! $$specs{txtQuantity1} ) {
      $$specs{alert} .= 'Please enter the quantity.';
      $Project->unlock();
      return $$specs{Status} = 'uncalculated';
      } # end if

      if ( $$specs{Status} eq 'uncalculated' ) {
      delete $$specs{txtPrice1};
      $$specs{alert} .= 'Problem calculating printing';
      $Project->unlock();
      return $$specs{Status};
      } # end if

# Force a reload
      $services = $Project->services(1);

#$log->debug("Adding Required Services");
      if ( openprint::Estimating::Cutting::neccessary( $Project ) and ! $$services{Cutting} ) {
        $openprint::log->debug("Adding Cutting") if DEBUG;
        push @{$$services{Cutting}}, $Project->add_service( 'Cutting' );
      } # end if

      push @{$$services{Proofs}}, $Project->add_service( 'Proofs' ) if ! $$services{Proofs};
      $openprint::log->debug("Proofs: $$specs{proof_type}");
      if ( exists $$specs{proof_type} ) {
        my $proof_specs = openprint::service::get_specs_ref( $Project, $$services{Proofs}[0] );
        my %proof_indexes;
        foreach my $signature_service_index ( $Project->signatures() ) {
          my $sig_specs = openprint::service::get_specs_ref( $Project, $signature_service_index );
          my $signature_index = $$sig_specs{SignatureIndex};
          foreach my $key ( keys %{$proof_specs} ) {
            if ( $key =~ /^txtProofIndex-$signature_index-(\d*)-1$/ ) {
              push @{$proof_indexes{$signature_index}}, $1;
            } # end if
          } # end foreach keys
          my $Imposition = new openprint::Imposition();
          $Imposition->load( $sig_specs, 1, $Project );

          if ( ( ! sets::isin( 1, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add Default Layout Proof'} eq 'Y' ) {
            push @{$proof_indexes{$signature_index}}, 1;
            openprint::Estimating::Proofs::insert_layout_proof( $sig_specs, 1, 1, $proof_specs, $Imposition );
          } # end if
          if ( ( ! sets::isin( 2, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add Default Colour Proof'} eq 'Y' ) {
            push @{$proof_indexes{$signature_index}}, 2;
            openprint::Estimating::Proofs::insert_colour_proof( $Project, $sig_specs, 2, 1, $proof_specs );
          } # end if
#$openprint::log->debug("Adding press proof $openprint::config{'Add Default Press Proof'}");
          if ( ( ! sets::isin( 3, $proof_indexes{$signature_index} ) ) and $openprint::config{'Add Default Press Proof'} eq 'Y' ) {
#$openprint::log->debug("Adding press proof");
            push @{$proof_indexes{$signature_index}}, 3;
            openprint::Estimating::Proofs::insert_press_proof( $Project, $sig_specs, 3, 1, $proof_specs, $Imposition );
          } # end if
          my $proof_index = 0;
          if ( $$specs{proof_type} ) {
            foreach ( @{$proof_indexes{$signature_index}} ) {
              $openprint::log->debug("Looking at $_ " . $$proof_specs{"ddmProofType-$signature_index-$_-1"} . ' for ' . $$specs{proof_type} );
              if ( $$proof_specs{"ddmProofType-$signature_index-$_-1"} eq $$specs{proof_type} ) {
                $proof_index = $_;
                last;
              } # end if
            } # end foreach proof_index
            if ( ! $proof_index ) {
              $proof_index = sets::max( $proof_indexes{$signature_index} ) + 1;
#$openprint::log->debug("Adding proof $proof_index");
              foreach my $qty_index ( $Project->quantity_indexes() ) {
#$$proof_specs{"txtProofQuantity-$signature_index-$proof_index-$qty_index"} = 1;
#$$proof_specs{"ddmProofType-$signature_index-$proof_index-$qty_index"} = $$specs{proof_type};
#$$proof_specs{"txtProofIndex-$signature_index-$proof_index-$qty_index"} = $proof_index;
                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "txtProofQuantity-$signature_index-$proof_index-$qty_index", 1);
                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "txtProofWidth-$signature_index-$proof_index-$qty_index", '' );
                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "txtProofHeight-$signature_index-$proof_index-$qty_index", '' );
                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "ddmProofType-$signature_index-$proof_index-$qty_index", $$specs{proof_type} );
                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "txtProofIndex-$signature_index-$proof_index-$qty_index", $proof_index );
              } # end foreach qty_index
            } # end if ! $proof_index
          } # end if $$specs{proof_type}

          foreach ( @{$proof_indexes{$signature_index}} ) {
            if ( ( $_ > 3 ) and ( $_ != $proof_index ) ) {
              foreach my $qty_index ( $Project->quantity_indexes() ) {

                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "ddmProofType-$signature_index-$_-$qty_index", '' );
                openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Proofs}[0], "txtProofQuantity-$signature_index-$_-$qty_index", 0 );
              } # end foreach qty_index
            } # end if
          } # end foreach proof_index
        } # end foreach signature

      } # end if exists rpoof_type

      if ( openprint::Estimating::Folding::neccessary( $Project ) ) {
        push @{$$services{Folding}}, $Project->add_service( 'Folding' ) if ! $$services{Folding};
        if ( (exists $$specs{FoldType}) and ((! $$specs{FoldType} ) or ( $$specs{FoldType} eq 'NoFold' )) ) {
          $$specs{alert} .= 'It appears that your project needs folding, but you have not selected the fold type.<br/>';
          $$specs{Status} = 'uncalculated';
        } # end if
      } elsif ( $$services{Folding} ) {
        foreach ( @{$$services{Folding}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end foreach
        delete $$services{Folding};
      } # end if

      if ( $$specs{HoleDrilling} eq 'Y' ) {
        push @{$$services{Drilling}}, $Project->add_service( 'Drilling' ) if ! $$services{Drilling};
        foreach my $sid ( @{$$services{Drilling}} ) {
          foreach my $spec ( 'txtHoleQty','txtHoleSize' ) {
            if ( $$specs{$spec} ne '' ) {
              openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, $spec, $$specs{$spec} ) 
            } else {
              @no_outputs = sets::exclude( [$spec], \@no_outputs );
            } # end if
          } # end foreach
        } # end foreach
      } elsif ( $$services{Drilling} ) {
        foreach ( @{$$services{Drilling}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end if
        delete $$services{Drilling};
      } # end if

      if ( ($$specs{Scoring} ne 'Y') and openprint::Estimating::Scoring::neccessary( $Project ) ) {
        $$specs{Scoring} = 'Y';
      } # end if

      if ( $$specs{Scoring} eq 'Y' ) {
        if ( ! $$services{Scoring} ) {
          push @{$$services{Scoring}}, $Project->add_service( 'Scoring' );
        } # end if
        my $scoring_specs = openprint::service::get_specs_ref( $Project, $$services{Scoring}[0] );
        my @sigs = $Project->signatures();
        my $sig_specs = openprint::service::get_specs_ref( $Project, $sigs[0] );

# Preload auto-calc # of scores, so we can determine if we need to override
        openprint::Estimating::Scoring::get_scores( $Project, $scoring_specs, $sig_specs );

        foreach my $sid ( @{$$services{Scoring}} ) {
          if ( ! ( $$specs{chkOverrideScoreQty} or $$scoring_specs{"txtVerticalQty-$$sig_specs{SignatureIndex}"} or $$scoring_specs{"txtHorizontalQty-$$sig_specs{SignatureIndex}"} ) ) {
            $$specs{chkOverrideScoreQty} = 'Y';
            $$specs{txtScoreQty} = 1;
          } # end if
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, "chkOverrideQty-$$sig_specs{SignatureIndex}", $$specs{chkOverrideScoreQty} );
          if ( $$specs{chkOverrideScoreQty} eq 'Y' ) {
            openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, "txtVerticalQty-$$sig_specs{SignatureIndex}", $$specs{txtScoreQty} );
            openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, "txtHorizontalQty-$$sig_specs{SignatureIndex}", 0 );
          } # end if
        } # end foreach
      } else {
        foreach ( @{$$services{Scoring}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end foreach
        delete $$services{Scoring};
      } # end if

      if ( $$specs{Perfing} eq 'Y' ) {
        push @{$$services{Perforating}}, $Project->add_service( 'Perforating' ) if ! $$services{Perforating};
        foreach my $sid ( @{$$services{Perforating}} ) {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'txtVerticalQty-0', $$specs{txtPerfQty} );
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'chkOverrideQty-0', 'Y' );
        } # end foreach
      } else {
        foreach ( @{$$services{Perforating}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end foreach
        delete $$services{Perforating};
      } # end if

      if ( $$services{Padding} ) {
        foreach my $service_id ( @{$$services{Padding}} ) {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $service_id, 'Backing', $$specs{Backing} ) if exists $$specs{Backing};
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $service_id, 'PageQuantity', $$specs{PageQuantity} ) if exists $$specs{PageQuantity};
        } # end foreach
      } # end if Padding

# Handle cartons
      my $ServiceType = openprint::ServiceType->find_one( type=>'PlainCartons' );
      if ( $ServiceType and sets::isin( $ServiceType->id(), $Project->Type()->blocked_services() ) ) {
        push @{$$services{PlainCartons}}, $Project->add_service( 'PlainCartons' ) if ! $$services{PlainCartons};
      } # end if

      if ( $$specs{UPSShipping} eq 'Y' ) {
        push @{$$services{UPS}}, $Project->add_service( 'UPS' ) if ! $$services{UPS};
        foreach my $sid ( @{$$services{UPS}} ) {
          foreach my $spec ( 'ToPostalCode','ToCountry','ddmServiceType','ddmPickupType' ) {
            openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, $spec, $$specs{$spec} );
          } # end foreach
        } # end foreach
      } else {
        foreach my $sid ( @{$$services{UPS}} ) {
          openprint::print_project::delete_service( $Project, $sid );
        } # end foreach
        delete $$services{UPS};
      } # end if

      push @{$$services{Turnaround}}, $Project->add_service( 'Turnaround' ) if ! $$services{Turnaround};

      if ( $$specs{ShrinkWrapping} eq 'Y' ) {
        if ( ! $$services{ShrinkWrap} ) {
          push @{$$services{ShrinkWrap}}, $Project->add_service( 'ShrinkWrap' );
        } # end if
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{ShrinkWrap}[0], 'txtItemsPerPackage', $$specs{txtItemsPerShrinkWrap} );
      } elsif ( $$services{ShrinkWrap} ) {
        foreach ( @{$$services{ShrinkWrap}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end foreach
        delete $$services{ShrinkWrap};
      } # end if

      if ( $$specs{Bundling} eq 'Y' ) {
        if ( ! $$services{Bundling} ) {
          push @{$$services{Bundling}}, $Project->add_service( 'Bundling' );
        } # end if
        openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Bundling}[0], 'txtItemsPerPackage', $$specs{txtItemsPerBundle} );
      } elsif ( $$services{Bundling} ) {
        foreach ( @{$$services{Bundling}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end foreach
        delete $$services{Bundling};
      } # end if

      if ( $$specs{LaminationType} or $$specs{LaminationTypeFront} or $$specs{LaminationTypeBack} ) {
        if ( ! $$services{Lamination} ) {
          push @{$$services{Lamination}}, $Project->add_service( 'Lamination' );
        } # end if
        if ( $$specs{LaminationType} ) {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Lamination}[0], 'TypeFront', $$specs{LaminationType} );
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Lamination}[0], 'TypeBack', $$specs{LaminationType} );
        } else {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Lamination}[0], 'TypeFront', $$specs{LaminationTypeFront} );
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $$services{Lamination}[0], 'TypeBack', $$specs{LaminationTypeBack} );
        } # end if

      } else {
        foreach ( @{$$services{Lamination}} ) {
          openprint::print_project::delete_service( $Project, $_ );
        } # end foreach
        delete $$services{Lamination};
      } # end if LaminationType

      foreach my $sid ( @{$$services{Turnaround}} ) {
        foreach my $spec ( 'TurnaroundDays' ) {
          openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, $spec, $$specs{$spec} );
        } # end foreach
      } # end foreach
      foreach my $service_name ( 'Design' ) {
        if ( $$specs{$service_name.'_txtQuantity'} ) {
          push @{$$services{$service_name}}, $Project->add_service($service_name) if ! $$services{$service_name};
          foreach my $sid ( @{$$services{$service_name}} ) {
            openprint::service::insert_service_spec( $log, $dbh, $$Project{id}, $sid, 'txtQuantity', $$specs{$service_name.'_txtQuantity'} );
          } # end foreach
        } else {
          foreach ( @{$$services{$service_name}} ) {
            openprint::print_project::delete_service( $Project, $_ );
          } # end foreach
          delete $$services{$service_name};
        } # end if
      }  # end foreach service_name

      my @s = $Project->signatures();
      $log->debug("Sigs: @s");
      $openprint::log->warn("Before auto");
      require "openprint/Estimating/$$ProjectType{type}.pm";
      my $module = 'openprint::Estimating::'.$$ProjectType{type};
      if ( my $function = $module->can( 'calculate_signatures' ) ) {
        $function->( $Project );
      } # end if

      $$specs{alert} .= openprint::service::auto_calculate( $Project );
      $openprint::log->warn("Aftere auto");
# Need to reload this because the auto calculation can add services, and we wouldn't otherwise pick them up
      my $services = $Project->services();

      if ( $$services{Scoring} ) {
        my $score_specs = openprint::service::get_specs_ref( $Project, $$services{Scoring}[0] );
        if ( $$specs{chkOverrideScoreQty} ne 'Y' ) {
          $$specs{txtScoreQty} = 0;
          foreach my $ss_id ( $Project->signatures() ) {
            my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
            $$specs{txtScoreQty} += $$score_specs{'txtVerticalQty-'.$$sig_specs{SignatureIndex}} + $$score_specs{'txtHorizontalQty-'.$$sig_specs{SignatureIndex}};
          } # end foreach
        } # end if
        if ( ! $$specs{txtScoreQty} ) {
          $$specs{alert} .= 'Please enter the # of scores.';
          $$specs{Status} = 'uncalculated';
        } # end if
      } # end if
      if ( $$services{Drilling} ) {
        my $drill_specs = openprint::service::get_specs_ref( $Project, $$services{Drilling}[0] );
        $$specs{txtHoleQty} = $$drill_specs{txtHoleQty};
      } # end if

      $$specs{txtPrice1} = 0;
      $$specs{txtUnitPrice1} = 0;
# add up the prices
#if ( $$specs{Status} ne 'uncalculated' ) {
  foreach my $service_name ( keys %{$services} ) {
    foreach my $service_index ( @{$$services{$service_name}} ) {
      my $service_specs = openprint::service::get_specs_ref( $Project, $service_index );
      $$specs{txtPrice1} += $$service_specs{txtPrice1};	
      if ( $$service_specs{Status} eq 'uncalculated' ) {
        $log->warn("$service_name is uncalculated");
        $$specs{Status} = 'uncalculated';
      } else {
        $log->warn("$service_name is calculated");
      } # en dif
#$log->debug("Prices for $service_name : $$service_specs{txtPrice1}");
    } # end foreach service_index
  } # end foreach service_name
#} else {
#$log->warn("Have uncalculated service: ");
#} # end if
  $log->warn("price: $$specs{txtPrice1}");
  $$specs{txtPrice1} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{txtPrice1} );
  $$specs{txtUnitPrice1} = Math::Round::nearest( 0.01, $$specs{txtPrice1}/$$specs{txtQuantity1} );	
  $log->warn("unitprice: $$specs{txtUnitPrice1}");
  $Project->price1( $$specs{txtPrice1} );
  $Project->summary(undef);
  if ( $_ = $Project->save() ) {
    $log->error( $_ );
  } # end if

  $$specs{ProductionPrice1} = $$specs{txtPrice1};
  $$specs{ShippingPrice1} = 0;
# Subtract shipping costs from total
  if ( $$services{UPS} ) {
    foreach my $service_id ( @{$$services{UPS}} ) {
      my $service_specs = openprint::service::get_specs_ref( $Project, $service_id );
      $$specs{ProductionPrice1} -= $$service_specs{txtPrice1};
      $$specs{ShippingPrice1} += $$service_specs{txtPrice1};
      $$specs{ServiceTypeDiv} = $$service_specs{ServiceTypeDiv};
      $$specs{PickupTypeDiv} = $$service_specs{PickupTypeDiv};
      $$specs{alert} .= $$service_specs{alert};
    } # end foreach service
  } # end if UPS
  $$specs{ShippingPrice1} = sprintf( '%.2f', Math::Round::nearest(0.01,$$specs{ShippingPrice1} ) );
  $$specs{ProductionPrice1} = sprintf( '%.2f', Math::Round::nearest(0.01,$$specs{ProductionPrice1} ) );

  $$specs{Status} = $Project->update_status( $variable );
  if ( $$specs{Status} ne 'Unordered' ) {
    $$specs{alert} = 'There was an error in calculations.  Please contact us for help.' if ! $$specs{alert};
    $$specs{txtPrice1} = '';
    $$specs{txtUnitPrice1} = '';
  } else {
    my %printing_types;
    foreach my $ss_id ( $Project->signatures() ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
      $printing_types{$$sig_specs{PrintingType1}} = 1;
    } # end foreach
    if ( %printing_types ) {
      $$specs{alert} .= 'This quote is for printing on ' . join(',', keys %printing_types ) . ' presses.<br/>';
    } # end if
  } # end if
  delete $$variable{Redirect};
  $Project->unlock();
  return $$specs{Status};
} # end sub calc


# This should not alter the db
sub create_calc {
  my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

  if ( $$specs{rdbProjectType} ) {
    my $ProjectType = openprint::ProjectType->find_one( name => $$specs{rdbProjectType} );
    if ( $ProjectType ) {
      my @required_servicetype_ids = $ProjectType->required_services();
      $openprint::log->debug("required service types @required_servicetype_ids");
      if ( @required_servicetype_ids ) {
        foreach my $ServiceType ( openprint::ServiceType->find( create_visible => 1, id=>\@required_servicetype_ids ) ) {
          $$specs{'chkServices'.$ServiceType->name()} = $ServiceType->name();
        } # end foreach
      } # end if required_servicetype_ids
      my @blocked_servicetype_ids = $ProjectType->blocked_services();
      if ( @blocked_servicetype_ids ) {
        foreach my $ServiceType ( openprint::ServiceType->find( create_visible => 1, id=>\@blocked_servicetype_ids ) ) {
          $$specs{'chkServices'.$ServiceType->name()} = '';
        } # end foreach
      } # end if blocked_servicetype_ids
    } # end if ProjectType
  } # end if $$specs{ProjectType}

  return $$specs{Status} = 'calculated';
} # end sub create_calc

# This version JUST does colours, not coatings
sub get_colours {
  my ( $specs, $side ) = @_;
  my @colours;
  if ( $$specs{sides_the_same} eq 'Y' and $side eq 'SideTwo' ) {
    $side = 'SideOne';
  } # end if

  foreach my $colour ( 'Cyan','Magenta','Yellow','Black' ) {
    if ( $$specs{'chk'.$colour.$side} ) {
      push @colours, "$colour Spot Colour";
    } # end if
  } # end foreach
  if ( $$specs{'chkProcessColour'.$side} ) {
    push @colours, 'Cyan','Magenta','Yellow','Black';
  } # end if

  foreach my $k ( keys %$specs ) {
    if ( my ( $index ) = $k =~ /^chkColourCoating(\d+)$side/ ) {
      next if ! $$specs{"chkColourCoating$index$side"};
      my $type = $$specs{"ColourCoatingType$index$side"};
      next if ! $type;
      next if $$specs{'ColourCoatingColour'.$index.$side} eq 'None';
#$openprint::log->debug("Found Colour $index.$side $signature $type");
      if ( $type =~ /PMS/ ) {
        push @colours, $$specs{'ColourCoatingColour'.$index.$side};
      } # end if type eq PMS
    } # end if
  } # end foreach
  return @colours;
} # end sub get_colours

1;

__END__
