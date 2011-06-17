module mercury_globals

!*************************************************************
!** Modules that contains all the globals variables of mercury
!**
!** Version 1.0 - june 2011
!*************************************************************
  use types_numeriques
  use mercury_constant

  implicit none
  
  integer, dimension(8) :: opt = (/0,1,1,2,0,1,0,0/) ! Default options (can be overwritten later in the code) for mercury.
  
  character(len=80), dimension(NMESS) :: mem ! Various messages and strings used by mercury
  integer, dimension(NMESS) :: lmem ! the length of each string of the 'mem' elements
  
  character(len=80), dimension(3) :: outfile
  character(len=80), dimension(4) :: dumpfile
  
  integer :: algor ! An index that represent the algorithm used. (may change over time, especially for the HYBRID integrator).
  
  real(double_precision) :: tstart ! TSTART = epoch of first required output (days)
  real(double_precision) :: tstop ! TSTOP  =   epoch final required output (days)
  
end module mercury_globals