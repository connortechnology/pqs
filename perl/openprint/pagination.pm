package openprint::pagination;

use strict;
use POSIX qw(ceil);

sub calculateOutput
{
   my ( 
         $totalResults,
         $radius,
         $cursor,
         $resultsPerPage,
         ) = @_;
   
   # $cursor - Current start position. ( $cursor to 500 of 1000 )
   # $resultsEnd - Number of last record. ( 1 to $resultsEnd of 1000 )
   # $totalResults - Total number of records. ( 1 to 500 of $totalResults )
   # $radius - How many links to pages we should see before and after the current page.
   # $resultsPerPage - Limit on the number of results to show per page.
   # $paginationWindow - Calculated number of page links to show.
   # $totalPages - Calculated number of total pages.
   # $currentPage - The current page.
   # $startPage - First page link to display.
   # $endPage - Last page link to display.
   # $previousPage - Page number of the previous page.
   # $nextPage - Page number of the next page.
   
   my $paginationWindow;
   my $totalPages;
   my $currentPage;
   my $startPage;
   my $endPage;
   my $resultsEnd;
   my $previousPage;
   my $nextPage;
   
   my %paginationResults;
   my @pages;
   my $offsetParam = $cursor;
   
   # Calculate total possible amount of pages.
   $totalPages = ceil($totalResults / $resultsPerPage);
   
   $paginationWindow = 2 * $radius + 1;
   
   adjustCursor(\$cursor, \$totalResults, \$resultsPerPage,);
   $currentPage = calculateCurrentPage(\$offsetParam, \$resultsPerPage,);
   calculateStartEndPages(\$currentPage,\$radius,\$startPage,\$endPage,\$paginationWindow,\$totalPages,);
   
   # Calculate $resultsEnd
   $resultsEnd = (($offsetParam + ($resultsPerPage)) - 1 < $totalResults) ? ($offsetParam + ($resultsPerPage)) - 1 : $totalResults;
   
   # Generate the pages array
   for(my $page = $startPage; $page <= $endPage; $page++)
   {
      my $offset;
      my %page;
      
      $offset = $resultsPerPage - 1;

      # Mark page as the current page.
      $page{currentPage} = 1 if($page == $currentPage);
      
      $page{pageNumber} = $page;
      $page{newCursor} = $page * $resultsPerPage - $offset;
      push(@pages, \%page);
   }
   
   # Generate previous page link.
   if($currentPage > 1)
   {
      $previousPage = $currentPage - 1;
   }
   
   # Generate next page link.
   if($currentPage < $totalPages)
   {
      $nextPage = $currentPage + 1;
   }
   
   # Prepare data to return.
   $paginationResults{offset} = ($offsetParam > 0) ? $offsetParam : 1;
   $paginationResults{paginationWindow} = $paginationWindow;
   $paginationResults{totalPages} = $totalPages;
   $paginationResults{currentPage} = $currentPage;
   $paginationResults{startPage} = $startPage;
   $paginationResults{endPage} = $endPage;
   $paginationResults{resultsEnd} = $resultsEnd;
   $paginationResults{previousPage} = $previousPage;
   $paginationResults{nextPage} = $nextPage;
   $paginationResults{pages} = \@pages;
   $paginationResults{nextOffset} = ($currentPage < $totalPages) ? $offsetParam + $resultsPerPage : -1;
   $paginationResults{previousOffset} = ($currentPage > 1) ? $offsetParam - $resultsPerPage : -1;
   
   $paginationResults{offset} = 0 if($totalResults == 0);
   
   return \%paginationResults;
}

sub adjustCursor
{
   my($cursor, $totalResults, $resultsPerPage,) = @_;
   
   my $offset;
   
   if($$cursor > $$totalResults)
   {
      $$cursor = $$totalResults;
   }
   
   if($$cursor < 1)
   {
      $$cursor = 1;
   }
   
   # how much cursor is off what it should be
   # ($$cursor - 1) must be divisible  by results_per_page
   $offset = (($$cursor - 1) % $$resultsPerPage);
   if($offset > 0)
   {
      $$cursor -= $offset;
   }
}

sub calculateCurrentPage
{
   my ( $cursor, $resultsPerPage, ) = @_;
   
   my $offset = $$resultsPerPage - 1;
   my $tmp = $$cursor + $offset;
   my $currentPage = ceil($tmp / $$resultsPerPage);

   return $currentPage;
}

sub calculateStartEndPages
{
   my ( $currentPage, $radius, $startPage, $endPage, $paginationWindow, $totalPages, ) = @_;
   
   my $inBeginning;
   my $inEnd;
   
   $inBeginning = (($$currentPage - $$radius) < 1) ? 1 : 0;
   $inEnd = (!$inBeginning && (($$currentPage + $$radius) > $$totalPages)) ? 1 : 0;
   
   if($inBeginning)
   {
      $$startPage = 1;
      $$endPage = ($$paginationWindow < $$totalPages) ? $$paginationWindow : $$totalPages;
   }
   elsif($inEnd)
   {
      $$startPage = (($$totalPages - ($$paginationWindow - 1)) > 1) ? ($$totalPages - ($$paginationWindow - 1)) : 1;
      $$endPage = $$totalPages;
   }
   else
   {
      $$startPage = $$currentPage - $$radius;
      $$endPage = $$currentPage + $$radius;
   }
}

return 1;