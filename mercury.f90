!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!      MERCURY.F90    (ErikSoft   3 May 2002)

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

! Author: John E. Chambers (and Christophe Cossou)

! Mercury is a general-purpose N-body integration package for problems in
! celestial mechanics.

!------------------------------------------------------------------------------
! This package contains some subroutines taken from the Swift integration 
! package by H.F.Levison and M.J.Duncan (1994) Icarus, vol 108, pp18.
! Routines taken from Swift have names beginning with `drift' or `orbel'.

! The standard symplectic (MVS) algorithm is described in J.Widsom and
! M.Holman (1991) Astronomical Journal, vol 102, pp1528.

! The hybrid symplectic algorithm is described in J.E.Chambers (1999)
! Monthly Notices of the RAS, vol 304, pp793.

! RADAU is described in E.Everhart (1985) in ``The Dynamics of Comets:
! Their Origin and Evolution'' p185-202, eds. A.Carusi & G.B.Valsecchi,
! pub. Reidel.

! The Bulirsch-Stoer algorithms are described in W.H.Press et al. (1992)
! ``Numerical Recipes in Fortran'', pub. Cambridge.
!------------------------------------------------------------------------------

! Variables:
! ---------
!  M      = mass (in solar masses)
!  XH     = coordinates (x,y,z) with respect to the central body (AU)
!  VH     = velocities (vx,vy,vz) with respect to the central body (AU/day)
!  S      = spin angular momentum (solar masses AU^2/day)
!  RHO    = physical density (g/cm^3)
!  RCEH   = close-encounter limit (Hill radii)
!  STAT   = status (0 => alive, <>0 => to be removed)
!  ID     = name of the object (8 characters)
!  CE     = close encounter status
!  NGF    = (1-3) cometary non-gravitational (jet) force parameters
!   "     =  (4)  beta parameter for radiation pressure and P-R drag
!  EPOCH  = epoch of orbit (days)
!  NBOD  = current number of bodies (INCLUDING the central object)
!  NBIG  =    "       "    " big bodies (ones that perturb everything else)
!  TIME  = current epoch (days)
!  TOUT  = time of next output evaluation
!  TDUMP = time of next data dump
!  TFUN  = time of next periodic effect (e.g. next check for ejections)
!  H     = current integration timestep (days)
!  EN(1) = initial energy of the system
!  " (2) = current    "    "  "    "
!  " (3) = energy change due to collisions, ejections etc.
!  AM(1,2,3) = as above but for angular momentum

! Integration Parameters :
! ----------------------
!  ALGOR = 1  ->  Mixed-variable symplectic
!          2  ->  Bulirsch-Stoer integrator
!          3  ->         "           "      (conservative systems only)
!          4  ->  RA15 `radau' integrator
!          10 ->  Hybrid MVS/BS (democratic-heliocentric coords)
!          11 ->  Close-binary hybrid (close-binary coords)
!          12 ->  Wide-binary hybrid (wide-binary coords)

! TSTART = epoch of first required output (days)
! TSTOP  =   "      final required output ( "  )
! DTOUT  = data output interval           ( "  )
! DTDUMP = data-dump interval             ( "  )
! DTFUN  = interval for other periodic effects (e.g. check for ejections)
!  H0    = initial integration timestep (days)
!  TOL   = Integrator tolerance parameter (approx. error per timestep)
!  RMAX  = heliocentric distance at which objects are considered ejected (AU)
!  RCEN  = radius of central body (AU)
!  JCEN(1,2,3) = J2,J4,J6 for central body (units of RCEN^i for Ji)

! Options:
!  OPT(1) = close-encounter option (0=stop after an encounter, 1=continue)
!  OPT(2) = collision option (0=no collisions, 1=merge, 2=merge+fragment)
!  OPT(3) = time style (0=days 1=Greg.date 2/3=days/years w/respect to start)
!  OPT(4) = o/p precision (1,2,3 = 4,9,15 significant figures)
!  OPT(5) = < Not used at present >
!  OPT(6) = < Not used at present >
!  OPT(7) = apply post-Newtonian correction? (0=no, 1=yes)
!  OPT(8) = apply user-defined force routine mfo_user? (0=no, 1=yes)

! File variables :
! --------------
!  OUTFILE  (1) = osculating coordinates/velocities and masses
!     "     (2) = close encounter details
!     "     (3) = information file
!  DUMPFILE (1) = Big-body data
!     "     (2) = Small-body data
!     "     (3) = integration parameters
!     "     (4) = restart file

! Flags :
! -----
!  NGFLAG = do any bodies experience non-grav. forces?
!                            ( 0 = no non-grav forces)
!                              1 = cometary jets only
!                              2 = radiation pressure/P-R drag only
!                              3 = both
!  OPFLAG = integration mode (-2 = synchronising epochs)
!                             -1 = integrating towards start epoch
!                              0 = main integration, normal output
!                              1 = main integration, full output

!------------------------------------------------------------------------------


program mercury
  use types_numeriques
  use physical_constant
  use mercury_constant
  use mercury_globals
  use system_properties
  use mercury_outputs
  use utilities
  
  ! ALGORITHMS
  use algo_hybrid
  use algo_mvs
  use algo_bs1
  use algo_bs2
  use algo_radau
  
  ! FORCES
  use forces

  implicit none
  
  integer :: j,algor,nbod,nbig,stat(NMAX),lmem(NMESS)
  integer :: opflag,ngflag,ndump,nfun
  integer :: error
  real(double_precision) :: m(NMAX),xh(3,NMAX),vh(3,NMAX),s(3,NMAX),rho(NMAX)
  real(double_precision) :: rceh(NMAX),epoch(NMAX),ngf(4,NMAX),rmax,rcen,jcen(3)
  real(double_precision) :: cefac,time,tstart,tstop,dtout,h0,tol,en(3),am(3)
  character*8 id(NMAX)
  character*80 outfile(3), dumpfile(4), mem(NMESS)
  
  !------------------------------------------------------------------------------
  
  ! Get initial conditions and integration parameters
  call mio_in (time,tstart,tstop,dtout,algor,h0,tol,rmax,rcen,jcen,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,stat,id,&
       epoch,ngf,opflag,ngflag,outfile,dumpfile,lmem,mem)
  
  ! If this is a new integration, integrate all the objects to a common epoch.
  if (opflag.eq.-2) then
     open (23,file=outfile(3),status='old',access='append',iostat=error)
     if (error /= 0) then
        write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(outfile(3))
        stop
     end if
     write (23,'(/,a)') mem(55)(1:lmem(55))
     write (*,'(a)') mem(55)(1:lmem(55))
     call mxx_sync (time,tstart,h0,tol,jcen,nbod,nbig,m,xh,vh,s,rho,rceh,stat,id,epoch,ngf,ngflag)
     write (23,'(/,a,/)') mem(56)(1:lmem(56))
     write (*,'(a)') mem(56)(1:lmem(56))
     opflag = -1
     close (23)
  end if
  
  ! Main integration
  if (algor.eq.1) call mal_hcon (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,&
       rho,rceh,stat,id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,mdt_mvs,mco_h2mvs,mco_mvs2h)
  
  if (algor.eq.9) call mal_hcon (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,&
       rho,rceh,stat,id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,mdt_mvs,mco_iden,mco_iden)
  
  if (algor.eq.2) call mal_hvar (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,&
       rho,rceh,stat,id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,mdt_bs1)
  
  if (algor.eq.3) call mal_hvar (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,&
       rho,rceh,stat,id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,mdt_bs2)
  
  if (algor.eq.4) call mal_hvar (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,&
       rho,rceh,stat,id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,mdt_ra15)
  
  if (algor.eq.10) call mal_hcon (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,&
       rho,rceh,stat,id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,mdt_hy,mco_h2dh,mco_dh2h)
  
  ! Do a final data dump
  do j = 2, nbod
     epoch(j) = time
  end do
  call mio_dump (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,stat,&
       id,ngf,epoch,opflag,dumpfile,mem,lmem)
  
  ! Calculate and record the overall change in energy and ang. momentum
  open  (23, file=outfile(3), status='old', access='append',iostat=error)
  if (error /= 0) then
     write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(outfile(3))
     stop
  end if
  write (23,'(/,a)') mem(57)(1:lmem(57))
  call mxx_en (jcen,nbod,nbig,m,xh,vh,s,en(2),am(2))
  
  write (23,231) mem(58)(1:lmem(58)),abs((en(2) + en(3) - en(1)) / en(1))
  write (23,232) mem(59)(1:lmem(59)), abs((am(2) + am(3) - am(1)) / am(1))
  write (23,231) mem(60)(1:lmem(60)), abs(en(3) / en(1))
  write (23,232) mem(61)(1:lmem(61)), abs(am(3) / am(1))
  close (23)
  write (*,'(a)') mem(57)(1:lmem(57))
  
  !------------------------------------------------------------------------------
  
231 format (/,a,1p1e12.5)
232 format (a,1p1e12.5)
  stop
  
  contains
  
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!      MIO_IN.FOR    (ErikSoft   4 May 2001)

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

! Author: John E. Chambers

! Reads names, masses, coordinates and velocities of all the bodies,
! and integration parameters for the MERCURY integrator package. 
! If DUMPFILE(4) exists, the routine assumes this is a continuation of
! an old integration, and reads all the data from the dump files instead
! of the input files.

! N.B. All coordinates are with respect to the central body!
! ===

!------------------------------------------------------------------------------

subroutine mio_in (time,tstart,tstop,dtout,algor,h0,tol,rmax,rcen,jcen,en,am,cefac,ndump,nfun,nbod,nbig,m,x,v,s,rho,rceh,stat,&
     id,epoch,ngf,opflag,ngflag,outfile,dumpfile,lmem,mem)
  
  use physical_constant
  use mercury_constant
  use orbital_elements

  implicit none

  
  ! Input/Output
  integer :: algor,nbod,nbig,stat(NMAX),opflag,ngflag
  integer :: lmem(NMESS),ndump,nfun
  real(double_precision) :: time,tstart,tstop,dtout,h0,tol,rmax,rcen,jcen(3)
  real(double_precision) :: en(3),am(3),m(NMAX),x(3,NMAX),v(3,NMAX),s(3,NMAX)
  real(double_precision) :: rho(NMAX),rceh(NMAX),epoch(NMAX),ngf(4,NMAX),cefac
  character*80 outfile(3),dumpfile(4), mem(NMESS)
  character*8 id(NMAX)
  
  ! Local
  integer :: j,k,itmp,jtmp,informat,lim(2,10),nsub,year,month,lineno
  real(double_precision) :: q,a,e,i,p,n,l,temp,tmp2,tmp3,rhocgs,t1,tmp4,tmp5,tmp6
  !      real(double_precision) :: v0(3,NMAX),x0(3,NMAX)
  logical test,oldflag,flag1,flag2
  character*1 c1
  character*3 c3
  character*80 infile(3),filename,c80
  character*150 string
  integer :: error

  character(len=3), dimension(60), parameter :: alg = (/'MVS','Mvs','mvs','mvs','mvs',&
      'BS ','Bs ','bs ','Bul', 'bul',&
      'BS2','Bs2','bs2','Bu2','bu2',&
       'RAD','Rad','rad','RA ', 'ra ',&
       'xxx','xxx','xxx','xxx','xxx',&
       'xxx','xxx','xxx','xxx', 'xxx',&
       'xxx','xxx','xxx','xxx','xxx',&
       'xxx','xxx','xxx','xxx', 'xxx',&
       'TES','Tes','tes','Tst','tst',&
       'HYB','Hyb','hyb','HY ', 'hy ',&
       'CLO','Clo','clo','CB ','cb ',&
       'WID','Wid','wid','WB ', 'wb '/)
  
  !------------------------------------------------------------------------------
    
  rhocgs = AU * AU * AU * K2 / MSUN
  do j = 1, 80
     filename(j:j) = ' '
  end do
  do j = 1, 3
     infile(j)   = filename
     outfile(j)  = filename
     dumpfile(j) = filename
  end do
  dumpfile(4) = filename
  
  ! Read in output messages
  inquire (file='message.in', exist=test)
  if (.not.test) then
     write (*,'(/,2a)') ' ERROR: This file is needed to start',' the integration:  message.in'
     stop
  end if
  open (16, file='message.in', status='old')
  do
     read (16,'(i3,1x,i2,1x,a80)', iostat=error) j,lmem(j),mem(j)
     if (error /= 0) exit
  end do
  close (16)
  
  ! Read in filenames and check for duplicate filenames
  inquire (file='files.in', exist=test)
  if (.not.test) call mio_err (6,mem(81),lmem(81),mem(88),lmem(88),' ',1,'files.in',8)
  open (15, file='files.in', status='old')
  
  ! Input files
  do j = 1, 3
     read (15,'(a150)') string
     call mio_spl (150,string,nsub,lim)
     infile(j)(1:(lim(2,1)-lim(1,1)+1)) = string(lim(1,1):lim(2,1))
     do k = 1, j - 1
        if (infile(j).eq.infile(k)) call mio_err (6,mem(81),lmem(81),mem(89),lmem(89),infile(j),80,mem(86),lmem(86))
     end do
  end do
  
  ! Output files
  do j = 1, 3
     read (15,'(a150)') string
     call mio_spl (150,string,nsub,lim)
     outfile(j)(1:(lim(2,1)-lim(1,1)+1)) = string(lim(1,1):lim(2,1))
     do k = 1, j - 1
        if (outfile(j).eq.outfile(k)) call mio_err (6,mem(81),lmem(81),mem(89),lmem(89),outfile(j),80,mem(86),lmem(86))
     end do
     do k = 1, 3
        if (outfile(j).eq.infile(k)) call mio_err (6,mem(81),lmem(81),mem(89),lmem(89),outfile(j),80,mem(86),lmem(86))
     end do
  end do
  
  ! Dump files
  do j = 1, 4
     read (15,'(a150)') string
     call mio_spl (150,string,nsub,lim)
     dumpfile(j)(1:(lim(2,1)-lim(1,1)+1)) = string(lim(1,1):lim(2,1))
     do k = 1, j - 1
        if (dumpfile(j).eq.dumpfile(k)) call mio_err (6,mem(81),lmem(81),mem(89),lmem(89),dumpfile(j),80,mem(86),lmem(86))
     end do
     do k = 1, 3
        if (dumpfile(j).eq.infile(k)) call mio_err (6,mem(81),lmem(81),mem(89),lmem(89),dumpfile(j),80,mem(86),lmem(86))
     end do
     do k = 1, 3
        if (dumpfile(j).eq.outfile(k)) call mio_err (6,mem(81),lmem(81),mem(89),lmem(89),dumpfile(j),80,mem(86),lmem(86))
     end do
  end do
  close (15)
  
  ! Find out if this is an old integration (i.e. does the restart file exist)
  inquire (file=dumpfile(4), exist=oldflag)
  
  ! Check if information file exists, and append a continuation message
  if (oldflag) then
     inquire (file=outfile(3), exist=test)
     if (.not.test) call mio_err (6,mem(81),lmem(81),mem(88),lmem(88),' ',1,outfile(3),80)
     open(23,file=outfile(3),status='old',access='append',iostat=error)
     if (error /= 0) then
        write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(outfile(3))
        stop
     end if
  else
     
     ! If new integration, check information file doesn't exist, and then create it
     inquire (file=outfile(3), exist=test)
     if (test) call mio_err (6,mem(81),lmem(81),mem(87),lmem(87),' ',1,outfile(3),80)
     open(23, file = outfile(3), status = 'new', iostat=error)
     if (error /= 0) then
        write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(outfile(3))
        stop
     end if
  end if
  
  !------------------------------------------------------------------------------
  
  !  READ  IN  INTEGRATION  PARAMETERS
  
  ! Check if the file containing integration parameters exists, and open it
  filename = infile(3)
  if (oldflag) filename = dumpfile(3)
  inquire (file=filename, exist=test)
  if (.not.test) call mio_err (23,mem(81),lmem(81),mem(88),lmem(88),' ',1,filename,80)
  open(13, file=filename, status='old', iostat=error)
  if (error /= 0) then
     write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(filename)
     stop
  end if
  
  ! Read integration parameters
  lineno = 0
  do j = 1, 26
     do
        lineno = lineno + 1
        read (13,'(a150)') string
        if (string(1:1).ne.')') exit
     end do

     call mio_spl (150,string,nsub,lim)
     c80(1:3) = '   '
     c80 = string(lim(1,nsub):lim(2,nsub))
     if (j.eq.1) then
        algor = 0
        do k = 1, 60
           if (c80(1:3).eq.alg(k)) algor = (k + 4) / 5
        end do
        if (algor.eq.0) call mio_err (23,mem(81),lmem(81),mem(98),lmem(98),c80(lim(1,nsub):lim(2,nsub)),lim(2,nsub)-lim(1,nsub)+1,&
             mem(85),lmem(85))
     end if
     if (j.eq.2) read (c80,*,err=661) tstart
     if (j.eq.3) read (c80,*,err=661) tstop
     if (j.eq.4) read (c80,*,err=661) dtout
     if (j.eq.5) read (c80,*,err=661) h0
     if (j.eq.6) read (c80,*,err=661) tol
     c1 = c80(1:1)
     if ((j.eq.7).and.((c1.eq.'y').or.(c1.eq.'Y'))) opt(1) = 1
     if ((j.eq.8).and.((c1.eq.'n').or.(c1.eq.'N'))) opt(2) = 0
     if ((j.eq.9).and.((c1.eq.'y').or.(c1.eq.'Y'))) opt(2) = 2
     if ((j.eq.10).and.((c1.eq.'d').or.(c1.eq.'D'))) opt(3) = 0
     if ((j.eq.11).and.((c1.eq.'y').or.(c1.eq.'Y'))) opt(3) = opt(3) + 2
     if (j.eq.12) then
        if((c1.eq.'l').or.(c1.eq.'L')) then
           opt(4) = 1
        else if (j.eq.12.and.(c1.eq.'m'.or.c1.eq.'M')) then
           opt(4) = 2
        else if (j.eq.12.and.(c1.eq.'h'.or.c1.eq.'H')) then
           opt(4) = 3
        else
           goto 661
        end if
     end if
     if (j.eq.15.and.(c1.eq.'y'.or.c1.eq.'Y')) opt(8) = 1
     if (j.eq.16) read (c80,*,err=661) rmax
     if (j.eq.17) read (c80,*,err=661) rcen
     if (j.eq.18) read (c80,*,err=661) m(1)
     if (j.eq.19) read (c80,*,err=661) jcen(1)
     if (j.eq.20) read (c80,*,err=661) jcen(2)
     if (j.eq.21) read (c80,*,err=661) jcen(3)
     if (j.eq.24) read (c80,*,err=661) cefac
     if (j.eq.25) read (c80,*,err=661) ndump
     if (j.eq.26) read (c80,*,err=661) nfun
  end do
  h0 = abs(h0)
  tol = abs(tol)
  rmax = abs(rmax)
  rcen = abs(rcen)
  cefac = abs(cefac)
  close (13)
  
  ! Change quantities for central object to suitable units
  m(1) = abs(m(1)) * K2
  jcen(1) = jcen(1) * rcen * rcen
  jcen(2) = jcen(2) * rcen * rcen * rcen * rcen
  jcen(3) = jcen(3) * rcen * rcen * rcen * rcen * rcen * rcen
  s(1,1) = 0.d0
  s(2,1) = 0.d0
  s(3,1) = 0.d0
  
  ! Make sure that RCEN isn't too small, since it is used to scale the output
  ! (Minimum value corresponds to a central body with density 100g/cm^3).
  temp = 1.1235d-3 * m(1) ** .333333333333333d0
  if (rcen.lt.temp) then
     rcen = temp
     write (13,'(/,2a)') mem(121)(1:lmem(121)),mem(131)(1:lmem(131))
  end if
  
  !------------------------------------------------------------------------------
  
  !  READ  IN  DATA  FOR  BIG  AND  SMALL  BODIES
  
  nbod = 1
  do j = 1, 2
     if (j.eq.2) nbig = nbod
     
     ! Check if the file containing data for Big bodies exists, and open it
     filename = infile(j)
     if (oldflag) filename = dumpfile(j)
     inquire (file=filename, exist=test)
     if (.not.test) call mio_err (23,mem(81),lmem(81),mem(88),lmem(88),' ',1,filename,80)
     open (11, file=filename, status='old', iostat=error)
     if (error /= 0) then
        write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(filename)
        stop
     end if
     
     ! Read data style
     
     do
      read (11,'(a150)') string
      if (string(1:1).ne.')') exit
    end do
     call mio_spl (150,string,nsub,lim)
     c3 = string(lim(1,nsub):(lim(1,nsub)+2))
     if (c3.eq.'Car'.or.c3.eq.'car'.or.c3.eq.'CAR') then
        informat = 1
     else if (c3.eq.'Ast'.or.c3.eq.'ast'.or.c3.eq.'AST') then
        informat = 2
     else if (c3.eq.'Com'.or.c3.eq.'com'.or.c3.eq.'COM') then
        informat = 3
     else
        call mio_err (23,mem(81),lmem(81),mem(91),lmem(91),' ',1,mem(82+j),lmem(82+j))
     end if
     
     ! Read epoch of Big bodies
     if (j.eq.1) then
      do
        read (11,'(a150)') string
        if (string(1:1).ne.')') exit
      end do
        call mio_spl (150,string,nsub,lim)
        read (string(lim(1,nsub):lim(2,nsub)),*,err=667) time
     end if
     
     ! Read information for each object
     do
      read (11,'(a)',iostat=error) string
      if (error /= 0) exit
      
      if (string(1:1).eq.')') cycle
    
     call mio_spl (150,string,nsub,lim)
     
     if (lim(1,1).eq.-1) exit
     
     ! Determine the name of the object
     nbod = nbod + 1
     if (nbod.gt.NMAX) call mio_err (23,mem(81),lmem(81),mem(90),lmem(90),' ',1,mem(82),lmem(82))
     
     if ((lim(2,1)-lim(1,1)).gt.7) then
        write (23,'(/,3a)') mem(121)(1:lmem(121)),mem(122)(1:lmem(122)),string( lim(1,1):lim(2,1) )
     end if
     id(nbod) = string( lim(1,1):min(7+lim(1,1),lim(2,1)) )
     ! Check if another object has the same name
     do k = 1, nbod - 1
        if (id(k).eq.id(nbod)) call mio_err (23,mem(81),lmem(81),mem(103),lmem(103),id(nbod),8,' ',1)
     end do
     
     ! Default values of mass, close-encounter limit, density etc.
     m(nbod) = 0.d0
     rceh(nbod) = 1.d0
     rho(nbod) = rhocgs
     epoch(nbod) = time
     do k = 1, 4
        ngf(k,nbod) = 0.d0
     end do
     
     ! Read values of mass, close-encounter limit, density etc.
     do k = 3, nsub, 2
        c80 = string(lim(1,k-1):lim(2,k-1))
        read (string(lim(1,k):lim(2,k)),*,err=666) temp
        if (c80(1:1).eq.'m'.or.c80(1:1).eq.'M') then
           m(nbod) = temp * K2
        else if (c80(1:1).eq.'r'.or.c80(1:1).eq.'R') then
           rceh(nbod) = temp
        else if (c80(1:1).eq.'d'.or.c80(1:1).eq.'D') then
           rho(nbod) = temp * rhocgs
        else if (m(nbod).lt.0.or.rceh(nbod).lt.0.or.rho(nbod).lt.0) then
           call mio_err (23,mem(81),lmem(81),mem(97),lmem(97),id(nbod),8,mem(82+j),lmem(82+j))
        else if (c80(1:2).eq.'ep'.or.c80(1:2).eq.'EP'.or.c80(1:2).eq.'Ep') then
           epoch (nbod) = temp
        else if (c80(1:2).eq.'a1'.or.c80(1:2).eq.'A1') then
           ngf (1,nbod) = temp
        else if (c80(1:2).eq.'a2'.or.c80(1:2).eq.'A2') then
           ngf (2,nbod) = temp
        else if (c80(1:2).eq.'a3'.or.c80(1:2).eq.'A3') then
           ngf (3,nbod) = temp
        else if (c80(1:1).eq.'b'.or.c80(1:1).eq.'B') then
           ngf (4,nbod) = temp
        else
           goto 666
        end if
     end do
     
     ! If required, read Cartesian coordinates, velocities and spins of the bodies
     jtmp = 100
     do
       read (11,'(a150)',end=666) string
       if (string(1:1).ne.')') exit
     end do 
     backspace 11
     if (informat.eq.1) then
        read (11,*,err=666) x(1,nbod),x(2,nbod),x(3,nbod),v(1,nbod),v(2,nbod),v(3,nbod),s(1,nbod),s(2,nbod),s(3,nbod)
     else
        read (11,*,err=666) a,e,i,p,n,l,s(1,nbod),s(2,nbod),s(3,nbod)
        i = i * DEG2RAD
        p = (p + n) * DEG2RAD
        n = n * DEG2RAD
        temp = m(nbod)  +  m(1)
        
        ! Alternatively, read Cometary or asteroidal elements
        if (informat.eq.3) then
           q = a
           a = q / (1.d0 - e)
           l = mod (sqrt(temp/(abs(a*a*a))) * (epoch(nbod) - l), TWOPI)
        else
           q = a * (1.d0 - e)
           l = l * DEG2RAD
        end if
        if ((algor.eq.11).and.(nbod.ne.2)) temp = temp + m(2)
        call mco_el2x (temp,q,e,i,p,n,l,x(1,nbod),x(2,nbod),x(3,nbod),v(1,nbod),v(2,nbod),v(3,nbod))
     end if
     
     s(1,nbod) = s(1,nbod) * K2
     s(2,nbod) = s(2,nbod) * K2
     s(3,nbod) = s(3,nbod) * K2
     
     
     end do
      close (11)
  end do
  
  ! Set non-gravitational-forces flag, NGFLAG
  ngflag = 0
  do j = 2, nbod
     if (ngf(1,j).ne.0.or.ngf(2,j).ne.0.or.ngf(3,j).ne.0) then
        if (ngflag.eq.0) ngflag = 1
        if (ngflag.eq.2) ngflag = 3
     else if (ngf(4,j).ne.0) then
        if (ngflag.eq.0) ngflag = 2
        if (ngflag.eq.1) ngflag = 3
     end if
  end do
  
  !------------------------------------------------------------------------------
  
  !  IF  CONTINUING  AN  OLD  INTEGRATION
  
  if (oldflag) then
     if (opt(3).eq.1) then
        call mio_jd2y (time,year,month,t1)
        write (23,'(/,a,i10,i2,f8.5,/)') mem(62)(1:lmem(62)),year,month,t1
     else if (opt(3).eq.3) then
        t1 = (time - tstart) / 365.25d0
        write (23,'(/,a,f18.7,a,/)') mem(62)(1:lmem(62)),t1,mem(2)(1:lmem(2))
     else
        if (opt(3).eq.0) t1 = time
        if (opt(3).eq.2) t1 = time - tstart
        write (23,'(/,a,f18.5,a,/)') mem(62)(1:lmem(62)),t1,mem(1)(1:lmem(1))
     end if
     
     ! Read in energy and angular momentum variables, and convert to internal units
     open (35, file=dumpfile(4), status='old', iostat=error)
     if (error /= 0) then
        write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(dumpfile(4))
        stop
     end if
     read (35,*) opflag
     read (35,*) en(1),am(1),en(3),am(3)
     en(1) = en(1) * K2
     en(3) = en(3) * K2
     am(1) = am(1) * K2
     am(3) = am(3) * K2
     read (35,*) s(1,1),s(2,1),s(3,1)
     s(1,1) = s(1,1) * K2
     s(2,1) = s(2,1) * K2
     s(3,1) = s(3,1) * K2
     close (35)
     if (opflag.eq.0) opflag = 1
     
     !------------------------------------------------------------------------------
     
     !  IF  STARTING  A  NEW  INTEGRATION
     
  else
     opflag = -2
     
     ! Write integration parameters to information file
     write (23,'(/,a)') mem(11)(1:lmem(11))
     write (23,'(a)') mem(12)(1:lmem(12))
     j = algor + 13
     write (23,'(/,2a)') mem(13)(1:lmem(13)),mem(j)(1:lmem(j))
     if (tstart.ge.1.d11.or.tstart.le.-1.d10) then
        write (23,'(/,a,1p,e19.13,a)') mem(26)(1:lmem(26)),tstart,mem(1)(1:lmem(1))
     else
        write (23,'(/,a,f19.7,a)') mem(26)(1:lmem(26)),tstart,mem(1)(1:lmem(1))
     end if
     if (tstop.ge.1.d11.or.tstop.le.-1.d10) then
        write (23,'(a,1p,e19.13)') mem(27)(1:lmem(27)),tstop
     else
        write (23,'(a,f19.7)') mem(27)(1:lmem(27)),tstop
     end if
     write (23,'(a,f15.3)') mem(28)(1:lmem(28)),dtout
     if (opt(4).eq.1) write (23,'(2a)') mem(40)(1:lmem(40)),mem(7)(1:lmem(7))
     if (opt(4).eq.2) write (23,'(2a)') mem(40)(1:lmem(40)),mem(8)(1:lmem(8))
     if (opt(4).eq.3) write (23,'(2a)') mem(40)(1:lmem(40)),mem(9)(1:lmem(9))
     
     write (23,'(/,a,f10.3,a)') mem(30)(1:lmem(30)),h0,mem(1)(1:lmem(1))
     write (23,'(a,1p1e10.4)') mem(31)(1:lmem(31)),tol
     write (23,'(a,1p1e10.4,a)') mem(32)(1:lmem(32)),m(1)/K2,mem(3)(1:lmem(3))
     write (23,'(a,1p1e11.4)') mem(33)(1:lmem(33)),jcen(1)/rcen**2
     write (23,'(a,1p1e11.4)') mem(34)(1:lmem(34)),jcen(2)/rcen**4
     write (23,'(a,1p1e11.4)') mem(35)(1:lmem(35)),jcen(3)/rcen**6
     write (23,'(a,1p1e10.4,a)') mem(36)(1:lmem(36)),rmax,mem (4)(1:lmem(4))
     write (23,'(a,1p1e10.4,a)') mem(37)(1:lmem(37)),rcen,mem (4)(1:lmem(4))
     
     itmp = 5
     if (opt(2).eq.1.or.opt(2).eq.2) itmp = 6
     write (23,'(/,2a)') mem(41)(1:lmem(41)),mem(itmp)(1:lmem(itmp))
     itmp = 5
     if (opt(2).eq.2) itmp = 6
     write (23,'(2a)') mem(42)(1:lmem(42)),mem(itmp)(1:lmem(itmp))
     itmp = 5
     if (opt(7).eq.1) itmp = 6
     write (23,'(2a)') mem(45)(1:lmem(45)),mem(itmp)(1:lmem(itmp))
     itmp = 5
     if (opt(8).eq.1) itmp = 6
     write (23,'(2a)') mem(46)(1:lmem(46)),mem(itmp)(1:lmem(itmp))
     
     ! Check that element and close-encounter files don't exist, and create them
     do j = 1, 2
        inquire (file=outfile(j), exist=test)
        if (test) call mio_err (23,mem(81),lmem(81),mem(87),lmem(87),' ',1,outfile(j),80)
        open  (20+j, file=outfile(j), status='new', iostat=error)
        if (error /= 0) then
           write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(outfile(j))
           stop
        end if
        close (20+j)
     end do
     
     ! Check that dump files don't exist, and then create them
     do j = 1, 4
        inquire (file=dumpfile(j), exist=test)
        if (test) call mio_err (23,mem(81),lmem(81),mem(87),lmem(87),' ',1,dumpfile(j),80)
        open  (30+j, file=dumpfile(j), status='new', iostat=error)
        if (error /= 0) then
           write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim(dumpfile(j))
           stop
        end if
        close (30+j)
     end do
     
     ! Write number of Big bodies and Small bodies to information file
     write (23,'(/,a,i4)') mem(38)(1:lmem(38)), nbig - 1
     write (23,'(a,i4)') mem(39)(1:lmem(39)), nbod - nbig
     
     ! Calculate initial energy and angular momentum and write to information file
     s(1,1) = 0.d0
     s(2,1) = 0.d0
     s(3,1) = 0.d0
     call mxx_en (jcen,nbod,nbig,m,x,v,s,en(1),am(1))
     write (23,'(//,a)') mem(51)(1:lmem(51))
     write (23,'(a)')    mem(52)(1:lmem(52))
     write (23,'(/,a,1p1e12.5,a)') mem(53)(1:lmem(53)),en(1)/K2,mem(72)(1:lmem(72))
     write (23,'(a,1p1e12.5,a)')   mem(54)(1:lmem(54)),am(1)/K2,mem(73)(1:lmem(73))
     
     ! Initialize lost energy and angular momentum
     en(3) = 0.d0
     am(3) = 0.d0
     
     ! Write warning messages if necessary
     if (tstop.lt.tstart) write (23,'(/,2a)') mem(121)(1:lmem(121)),mem(123)(1:lmem(123))
     if (nbig.le.0) write (23,'(/,2a)') mem(121)(1:lmem(121)),mem(124)(1:lmem(124))
     if (nbig.eq.nbod) write (23,'(/,2a)') mem(121)(1:lmem(121)),mem(125)(1:lmem(125))
  end if
  
  !------------------------------------------------------------------------------
  
  !  CHECK  FOR  ATTEMPTS  TO  DO  INCOMPATIBLE  THINGS
  
  ! If using close-binary algorithm, set radius of central body to be no less
  ! than the periastron of binary star.
  if (algor.eq.11) then
     temp = m(1) + m(2)
     call mco_x2el (temp,x(1,2),x(2,2),x(3,2),v(1,2),v(2,2),v(3,2),a,tmp2,tmp3,tmp4,tmp5,tmp6)
     rcen = max (rcen, a)
  end if
  
  ! Check if non-grav forces are being used with an incompatible algorithm
  if ((ngflag.ne.0).and.((algor.eq.3).or.(algor.eq.11).or.(algor.eq.12))) then
     call mio_err (23,mem(81),lmem(81),mem(92),lmem(92),' ',1,mem(85),lmem(85))
  endif
  
  ! Check if user-defined force routine is being used with wrong algorithm
  if ((opt(8).eq.1).and.((algor.eq.11).or.(algor.eq.12))) call mio_err(23,mem(81),lmem(81),mem(93),lmem(93),' ',1,mem(85),lmem(85))
  
  ! Check whether MVS is being used to integrate massive Small bodies,
  ! or whether massive Small bodies have different epochs than Big bodies.
  flag1 = .false.
  flag2 = .false.
  do j = nbig + 1, nbod
     if (m(j).ne.0) then
        if (algor.eq.1) call mio_err (23,mem(81),lmem(81),mem(94),lmem(94),' ',1,mem(85),lmem(85))
        flag1 = .true.
     end if
     if (epoch(j).ne.time) flag2 = .true.
  end do
  if (flag1.and.flag2) call mio_err (23,mem(81),lmem(81),mem(95),  lmem(95),' ',1,mem(84),lmem(84))
  
  ! Check if central oblateness is being used with close-binary algorithm
  if (algor.eq.11.and.(jcen(1).ne.0.or.jcen(2).ne.0.or.jcen(3).ne.0)) then
     call mio_err (23,mem(81),lmem(81),mem(102),lmem(102),' ',1,mem(85),lmem(85))
  endif
  
  ! Check whether RCEN > RMAX or RMAX/RCEN is very large
  if (rcen.gt.rmax) call mio_err (23,mem(81),lmem(81),mem(105),lmem(105),' ',1,mem(85),lmem(85))
  if (rmax/rcen.ge.1.d12) write (23,'(/,2a,/a)') mem(121)(1:lmem(121)),mem(106)(1:lmem(106)),mem(85)(1:lmem(85))
  close (23)
  return
  
  ! Error reading from the input file containing integration parameters
661 write (c3,'(i3)') lineno
  call mio_err (23,mem(81),lmem(81),mem(99),lmem(99),c3,3,mem(85),lmem(85))
  
  ! Error reading from the input file for Big or Small bodies
666 call mio_err (23,mem(81),lmem(81),mem(100),lmem(100),id(nbod),8,mem(82+j),lmem(82+j))
  
  ! Error reading epoch of Big bodies
667 call mio_err (23,mem(81),lmem(81),mem(101),lmem(101),' ',1,mem(83),lmem(83))
  
  !------------------------------------------------------------------------------
  
end subroutine mio_in

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!      MAL_HVAR.FOR    (ErikSoft   4 March 2001)

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

! Author: John E. Chambers

! Does an integration using a variable-timestep integration algorithm. The
! particular integrator routine is ONESTEP and the algorithm must use
! coordinates with respect to the central body.

! N.B. This routine is also called by the synchronisation routine mxx_sync,
! ===  in which case OPFLAG = -2. Beware when making changes involving OPFLAG.

!------------------------------------------------------------------------------

subroutine mal_hvar (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,stat,&
     id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,onestep)
  
  use physical_constant
  use mercury_constant
  use dynamic

  implicit none

  
  ! Input/Output
  integer :: algor,nbod,nbig,stat(nbod),opflag,ngflag,ndump,nfun
  integer :: lmem(NMESS)
  real(double_precision) :: time,tstart,tstop,dtout,h0,tol,jcen(3),rcen,rmax
  real(double_precision) :: en(3),am(3),cefac,m(nbod),xh(3,nbod),vh(3,nbod)
  real(double_precision) :: s(3,nbod),rho(nbod),rceh(nbod),ngf(4,nbod)
  character*8 id(nbod)
  character*80 outfile(3),dumpfile(4),mem(NMESS)
  
  ! Local
  integer :: i,j,k,n,itmp,nhit,ihit(CMAX),jhit(CMAX),chit(CMAX)
  integer :: dtflag,ejflag,nowflag,stopflag,nstored,ce(NMAX)
  integer :: nclo,iclo(CMAX),jclo(CMAX),nce,ice(NMAX),jce(NMAX)
  real(double_precision) :: tmp0,h,hdid,tout,tdump,tfun,tlog,tsmall,dtdump,dtfun
  real(double_precision) :: thit(CMAX),dhit(CMAX),thit1,x0(3,NMAX),v0(3,NMAX)
  real(double_precision) :: rce(NMAX),rphys(NMAX),rcrit(NMAX),a(NMAX)
  real(double_precision) :: dclo(CMAX),tclo(CMAX),epoch(NMAX)
  real(double_precision) :: ixvclo(6,CMAX),jxvclo(6,CMAX)
  external onestep
  
  !------------------------------------------------------------------------------
  
  ! Initialize variables. DTFLAG = 0 implies first ever call to ONESTEP
  dtout  = abs(dtout)
  dtdump = abs(h0) * ndump
  dtfun  = abs(h0) * nfun
  dtflag = 0
  nstored = 0
  tsmall = h0 * 1.d-8
  h = h0
  do j = 2, nbod
     ce(j) = 0.d0
  end do
  
  ! Calculate close-encounter limits and physical radii for massive bodies
  call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),1)
  
  ! Set up time of next output, times of previous dump, log and periodic effect
  if (opflag.eq.-1) then
     tout = tstart
  else
     n = int (abs (time - tstart) / dtout) + 1
     tout = tstart  +  dtout * sign (dble(n), tstop - tstart)
     if ((tstop - tstart)*(tout - tstop).gt.0) tout = tstop
  end if
  tdump = time
  tfun  = time
  tlog  = time
  
  !------------------------------------------------------------------------------
  
  !  MAIN  LOOP  STARTS  HERE
  
  do
     
     ! Is it time for output ?
     if (abs(tout-time).lt.abs(tsmall).and.opflag.ge.-1) then
        
        ! Beware: the integration may change direction at this point!!!
        if (opflag.eq.-1) dtflag = 0
        
        ! Output data for all bodies
        call mio_out (time,jcen,rcen,rmax,nbod,nbig,m,xh,vh,s,rho,stat,id,opflag,algor,outfile(1))
        call mio_ce (time,tstart,rcen,rmax,nbod,nbig,m,stat,id,0,iclo,jclo,stopflag,tclo,dclo,ixvclo,jxvclo,mem,lmem,outfile,&
             nstored,0)
        tmp0 = tstop - tout
        tout = tout + sign( min( abs(tmp0), abs(dtout) ), tmp0 )
        
        ! Update the data dump files
        do j = 2, nbod
           epoch(j) = time
        end do
        call mio_dump (time,tstart,tstop,dtout,algor,h,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,stat,&
             id,ngf,epoch,opflag,dumpfile,mem,lmem)
        tdump = time
     end if
     
     ! If integration has finished return to the main part of programme
     if (abs(tstop-time).le.abs(tsmall).and.opflag.ne.-1) return
     
     ! Set the timestep
     if (opflag.eq.-1) tmp0 = tstart - time
     if (opflag.eq.-2) tmp0 = tstop  - time
     if (opflag.ge.0)  tmp0 = tout   - time
     h = sign ( max( min( abs(tmp0), abs(h) ), tsmall), tmp0 )
     
     ! Save the current coordinates and velocities
     x0(:,:) = xh(:,:)
     v0(:,:) = vh(:,:)
!~      call mco_iden (time,jcen,nbod,nbig,h,m,xh,vh,x0,v0,ngf,ngflag)
     
     ! Advance one timestep
     call onestep (time,h,hdid,tol,jcen,nbod,nbig,m,xh,vh,s,rphys,rcrit,ngf,stat,dtflag,ngflag,nce,ice,jce,mfo_all)
     time = time + hdid
     
     ! Check if close encounters or collisions occurred
     nclo = 0
     call mce_stat (time,h,rcen,nbod,nbig,m,x0,v0,xh,vh,rce,rphys,nclo,iclo,jclo,dclo,tclo,ixvclo,jxvclo,nhit,ihit,jhit,chit,dhit,&
          thit,thit1,nowflag,stat,outfile(3),mem,lmem)
     
     !------------------------------------------------------------------------------
     
     !  CLOSE  ENCOUNTERS
     
     ! If encounter minima occurred, output details and decide whether to stop
     if (nclo.gt.0.and.opflag.ge.-1) then
        itmp = 1
        if (nhit.ne.0) itmp = 0
        call mio_ce (time,tstart,rcen,rmax,nbod,nbig,m,stat,id,nclo,iclo,jclo,stopflag,tclo,dclo,ixvclo,jxvclo,&
             mem,lmem,outfile,nstored,itmp)
        if (stopflag.eq.1) return
     end if
     
     !------------------------------------------------------------------------------
     
     !  COLLISIONS
     
     ! If a collision occurred, output details and resolve the collision
     if (nhit.gt.0.and.opt(2).ne.0) then
        do k = 1, nhit
           if (chit(k).eq.1) then
              i = ihit(k)
              j = jhit(k)
              call mce_coll (thit(k),tstart,en(3),jcen,i,j,nbod,nbig,m,xh,vh,s,rphys,stat,id,mem,lmem,outfile(3))
           end if
        end do
        
        ! Remove lost objects, reset flags and recompute Hill and physical radii
        call mxx_elim (nbod,nbig,m,xh,vh,s,rho,rceh,rcrit,ngf,stat,id,mem,lmem,outfile(3),itmp)
        dtflag = 1
        if (opflag.ge.0) opflag = 1
        call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),1)
     end if
     
     !------------------------------------------------------------------------------
     
     !  COLLISIONS  WITH  CENTRAL  BODY
     
     ! Check for collisions
     call mce_cent (time,hdid,rcen,jcen,2,nbod,nbig,m,x0,v0,xh,vh,nhit,jhit,thit,dhit,algor,ngf,ngflag)
     
     ! Resolve the collisions
     if (nhit.gt.0) then
        do k = 1, nhit
           i = 1
           j = jhit(k)
           call mce_coll (thit(k),tstart,en(3),jcen,i,j,nbod,nbig,m,xh,vh,s,rphys,stat,id,mem,lmem,outfile(3))
        end do
        
        ! Remove lost objects, reset flags and recompute Hill and physical radii
        call mxx_elim (nbod,nbig,m,xh,vh,s,rho,rceh,rcrit,ngf,stat,id,mem,lmem,outfile(3),itmp)
        dtflag = 1
        if (opflag.ge.0) opflag = 1
        call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),0)
     end if
     
     !------------------------------------------------------------------------------
     
     !  DATA  DUMP  AND  PROGRESS  REPORT
     
     ! Do the data dump
     if (abs(time-tdump).ge.abs(dtdump).and.opflag.ge.-1) then
        do j = 2, nbod
           epoch(j) = time
        end do
        call mio_ce (time,tstart,rcen,rmax,nbod,nbig,m,stat,id,0,iclo,jclo,stopflag,tclo,dclo,ixvclo,jxvclo,mem,lmem,outfile,&
             nstored,0)
        call mio_dump (time,tstart,tstop,dtout,algor,h,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,stat,&
             id,ngf,epoch,opflag,dumpfile,mem,lmem)
        tdump = time
     end if
     
     ! Write a progress report to the log file
     if (abs(time-tlog).ge.abs(dtdump).and.opflag.ge.0) then
        call mxx_en (jcen,nbod,nbig,m,xh,vh,s,en(2),am(2))
        call mio_log (time,tstart,en,am,mem,lmem)
        tlog = time
     end if
     
     !------------------------------------------------------------------------------
     
     !  CHECK  FOR  EJECTIONS  AND  DO  OTHER  PERIODIC  EFFECTS
     
     if (abs(time-tfun).ge.abs(dtfun).and.opflag.ge.-1) then
        
        ! Recompute close encounter limits, to allow for changes in Hill radii
        call mce_hill (nbod,m,xh,vh,rce,a)
        do j = 2, nbod
           rce(j) = rce(j) * rceh(j)
        end do
        
        ! Check for ejections
        call mxx_ejec (time,tstart,rmax,en,am,jcen,2,nbod,nbig,m,xh,vh,s,stat,id,ejflag,outfile(3),mem,lmem)
        
        ! Remove lost objects, reset flags and recompute Hill and physical radii
        if (ejflag.ne.0) then
           call mxx_elim (nbod,nbig,m,xh,vh,s,rho,rceh,rcrit,ngf,stat,id,mem,lmem,outfile(3),itmp)
           dtflag = 1
           if (opflag.ge.0) opflag = 1
           call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),0)
        end if
        tfun = time
     end if
     
     ! Go on to the next time step
  end do
  
  !------------------------------------------------------------------------------
  
end subroutine mal_hvar

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!      MAL_HCON.FOR    (ErikSoft   28 March 2001)

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

! Author: John E. Chambers

! Does an integration using an integrator with a constant stepsize H.
! Input and output to this routine use coordinates XH, and velocities VH,
! with respect to the central body, but the integration algorithm uses
! its own internal coordinates X, and velocities V.

! The programme uses the transformation routines COORD and BCOORD to change
! to and from the internal coordinates, respectively.

!------------------------------------------------------------------------------

subroutine mal_hcon (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,stat,&
     id,ngf,opflag,ngflag,outfile,dumpfile,mem,lmem,onestep,coord,bcoord)
  
  use physical_constant
  use mercury_constant
  use dynamic

  implicit none

  
  ! Input/Output
  integer :: algor,nbod,nbig,stat(nbod),opflag,ngflag
  integer :: lmem(NMESS),ndump,nfun
  real(double_precision) :: time,tstart,tstop,dtout,h0,tol,jcen(3),rcen,rmax
  real(double_precision) :: en(3),am(3),cefac,m(nbod),xh(3,nbod),vh(3,nbod)
  real(double_precision) :: s(3,nbod),rho(nbod),rceh(nbod),ngf(4,nbod)
  character*8 id(nbod)
  character*80 outfile(3),dumpfile(4),mem(NMESS)
  
  ! Local
  integer :: i,j,k,n,itmp,nclo,nhit,jhit(CMAX),iclo(CMAX),jclo(CMAX)
  integer :: dtflag,ejflag,stopflag,colflag,nstored
  real(double_precision) :: x(3,NMAX),v(3,NMAX),xh0(3,NMAX),vh0(3,NMAX)
  real(double_precision) :: rce(NMAX),rphys(NMAX),rcrit(NMAX),epoch(NMAX)
  real(double_precision) :: hby2,tout,tmp0,tdump,tfun,tlog,dtdump,dtfun
  real(double_precision) :: dclo(CMAX),tclo(CMAX),dhit(CMAX),thit(CMAX)
  real(double_precision) :: ixvclo(6,CMAX),jxvclo(6,CMAX),a(NMAX)
  external onestep,coord,bcoord
  
  !------------------------------------------------------------------------------
  
  ! Initialize variables. DTFLAG = 0/2: first call ever/normal
  dtout  = abs(dtout)
  dtdump = abs(h0) * ndump
  dtfun  = abs(h0) * nfun
  dtflag = 0
  nstored = 0
  hby2 = 0.500001d0 * abs(h0)
  
  ! Calculate close-encounter limits and physical radii
  call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),1)
  
  ! Set up time of next output, times of previous dump, log and periodic effect
  if (opflag.eq.-1) then
     tout = tstart
  else
     n = int (abs (time-tstart) / dtout) + 1
     tout = tstart  +  dtout * sign (dble(n), tstop - tstart)
     if ((tstop-tstart)*(tout-tstop).gt.0) tout = tstop
  end if
  tdump = time
  tfun  = time
  tlog  = time
  
  ! Convert to internal coordinates and velocities
  call coord (time,jcen,nbod,nbig,h0,m,xh,vh,x,v,ngf,ngflag)
  
  !------------------------------------------------------------------------------
  
  !  MAIN  LOOP  STARTS  HERE
  
  do
     
     ! Is it time for output ?
     if (abs(tout-time).le.hby2.and.opflag.ge.-1) then
        
        ! Beware: the integration may change direction at this point!!!
        if ((opflag.eq.-1).and.(dtflag.ne.0)) dtflag = 1
        
        ! Convert to heliocentric coordinates and output data for all bodies
        call bcoord (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        call mio_out (time,jcen,rcen,rmax,nbod,nbig,m,xh,vh,s,rho,stat,id,opflag,algor,outfile(1))
        call mio_ce (time,tstart,rcen,rmax,nbod,nbig,m,stat,id,0,iclo,jclo,stopflag,tclo,dclo,ixvclo,jxvclo,mem,lmem,outfile,&
             nstored,0)
        tmp0 = tstop - tout
        tout = tout + sign( min( abs(tmp0), abs(dtout) ), tmp0 )
        
        ! Update the data dump files
        do j = 2, nbod
           epoch(j) = time
        end do
        call mio_dump (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,&
             stat,id,ngf,epoch,opflag,dumpfile,mem,lmem)
        tdump = time
     end if
     
     ! If integration has finished, convert to heliocentric coords and return
     if (abs(tstop-time).le.hby2.and.opflag.ge.0) then
        call bcoord (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        return
     end if
     
     ! Make sure the integration is heading in the right direction
     ! The timestep will be redo if there are collisions with central body. Else, we exit the loop in the last 'if' statement.
     do
        tmp0 = tstop - time
        if (opflag.eq.-1) tmp0 = tstart - time
        h0 = sign (h0, tmp0)
        
        ! Save the current heliocentric coordinates and velocities
        if (algor.eq.1) then
          xh0(:,:) = x(:,:)
          vh0(:,:) = v(:,:)
!~            call mco_iden (time,jcen,nbod,nbig,h0,m,x,v,xh0,vh0,ngf,ngflag)
        else
           call bcoord(time,jcen,nbod,nbig,h0,m,x,v,xh0,vh0,ngf,ngflag)
        end if
        call onestep (time,tstart,h0,tol,rmax,en,am,jcen,rcen,nbod,nbig,m,x,v,s,rphys,rcrit,rce,stat,id,ngf,algor,dtflag,&
             ngflag,opflag,colflag,nclo,iclo,jclo,dclo,tclo,ixvclo,jxvclo,outfile,mem,lmem)
        time = time + h0
        
        !------------------------------------------------------------------------------
        
        !  CLOSE  ENCOUNTERS
        
        ! If encounter minima occurred, output details and decide whether to stop
        if ((nclo.gt.0).and.(opflag.ge.-1)) then
           itmp = 1
           if (colflag.ne.0) itmp = 0
           call mio_ce (time,tstart,rcen,rmax,nbod,nbig,m,stat,id,nclo,iclo,jclo,stopflag,tclo,dclo,ixvclo,jxvclo,mem,lmem,&
                outfile,nstored,itmp)
           if (stopflag.eq.1) return
        end if
        
        !------------------------------------------------------------------------------
        
        !  COLLISIONS
        
        ! If collisions occurred, output details and remove lost objects
        if (colflag.ne.0) then
           
           ! Reindex the surviving objects
           call bcoord (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
           call mxx_elim (nbod,nbig,m,xh,vh,s,rho,rceh,rcrit,ngf,stat,id,mem,lmem,outfile(3),itmp)
           
           ! Reset flags, and calculate new Hill radii and physical radii
           dtflag = 1
           if (opflag.ge.0) opflag = 1
           call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),1)
           call coord (time,jcen,nbod,nbig,h0,m,xh,vh,x,v,ngf,ngflag)
        end if
        
        !------------------------------------------------------------------------------
        
        !  COLLISIONS  WITH  CENTRAL  BODY
        
        ! Check for collisions with the central body
        if (algor.eq.1) then
          xh(:,:) = x(:,:)
          vh(:,:) = v(:,:)
!~            call mco_iden(time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        else
           call bcoord (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        end if
        itmp = 2
        if ((algor.eq.11).or.(algor.eq.12)) itmp = 3
        call mce_cent (time,h0,rcen,jcen,itmp,nbod,nbig,m,xh0,vh0,xh,vh,nhit,jhit,thit,dhit,algor,ngf,ngflag)
        
        ! If something hit the central body, restore the coords prior to this step
        if (nhit.eq.0) then
           exit
        else 
           ! Redo that integration time step
           xh(:,:) = xh0(:,:)
           vh(:,:) = vh0(:,:)
!~            call mco_iden (time,jcen,nbod,nbig,h0,m,xh0,vh0,xh,vh,ngf,ngflag)
           time = time - h0
           
           ! Merge the object(s) with the central body
           do k = 1, nhit
              i = 1
              j = jhit(k)
              call mce_coll (thit(k),tstart,en(3),jcen,i,j,nbod,nbig,m,xh,vh,s,rphys,stat,id,mem,lmem,outfile(3))
           end do
           
           ! Remove lost objects, reset flags and recompute Hill and physical radii
           call mxx_elim (nbod,nbig,m,xh,vh,s,rho,rceh,rcrit,ngf,stat,id,mem,lmem,outfile(3),itmp)
           if (opflag.ge.0) opflag = 1
           dtflag = 1
           call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),0)
           if (algor.eq.1) then
              x(:,:) = xh(:,:)
              v(:,:) = vh(:,:)
!~               call mco_iden (time,jcen,nbod,nbig,h0,m,xh,vh,x,v,ngf,ngflag)
           else
              call coord (time,jcen,nbod,nbig,h0,m,xh,vh,x,v,ngf,ngflag)
           end if
           
        end if
     end do
     
     !------------------------------------------------------------------------------
     
     !  DATA  DUMP  AND  PROGRESS  REPORT
     
     ! Convert to heliocentric coords and do the data dump
     if (abs(time-tdump).ge.abs(dtdump).and.opflag.ge.-1) then
        call bcoord (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        do j = 2, nbod
           epoch(j) = time
        end do
        call mio_ce (time,tstart,rcen,rmax,nbod,nbig,m,stat,id,0,iclo,jclo,stopflag,tclo,dclo,ixvclo,jxvclo,mem,lmem,outfile,&
             nstored,0)
        call mio_dump (time,tstart,tstop,dtout,algor,h0,tol,jcen,rcen,rmax,en,am,cefac,ndump,nfun,nbod,nbig,m,xh,vh,s,rho,rceh,&
             stat,id,ngf,epoch,opflag,dumpfile,mem,lmem)
        tdump = time
     end if
     
     ! Convert to heliocentric coords and write a progress report to the log file
     if (abs(time-tlog).ge.abs(dtdump).and.opflag.ge.0) then
        call bcoord (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        call mxx_en (jcen,nbod,nbig,m,xh,vh,s,en(2),am(2))
        call mio_log (time,tstart,en,am,mem,lmem)
        tlog = time
     end if
     
     !------------------------------------------------------------------------------
     
     !  CHECK  FOR  EJECTIONS  AND  DO  OTHER  PERIODIC  EFFECTS
     
     if (abs(time-tfun).ge.abs(dtfun).and.opflag.ge.-1) then
        if (algor.eq.1) then
           xh(:,:) = x(:,:)
           vh(:,:) = v(:,:)
!~            call mco_iden (time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        else
           call bcoord(time,jcen,nbod,nbig,h0,m,x,v,xh,vh,ngf,ngflag)
        end if
        
        ! Recompute close encounter limits, to allow for changes in Hill radii
        call mce_hill (nbod,m,xh,vh,rce,a)
        do j = 2, nbod
           rce(j) = rce(j) * rceh(j)
        end do
        
        ! Check for ejections
        itmp = 2
        if ((algor.eq.11).or.(algor.eq.12)) itmp = 3
        call mxx_ejec (time,tstart,rmax,en,am,jcen,itmp,nbod,nbig,m,xh,vh,s,stat,id,ejflag,outfile(3),mem,lmem)
        
        ! Remove ejected objects, reset flags, calculate new Hill and physical radii
        if (ejflag.ne.0) then
           call mxx_elim (nbod,nbig,m,xh,vh,s,rho,rceh,rcrit,ngf,stat,id,mem,lmem,outfile(3),itmp)
           if (opflag.ge.0) opflag = 1
           dtflag = 1
           call mce_init (tstart,algor,h0,jcen,rcen,rmax,cefac,nbod,nbig,m,xh,vh,s,rho,rceh,rphys,rce,rcrit,id,outfile(2),0)
           if (algor.eq.1) then
              x(:,:) = xh(:,:)
              v(:,:) = vh(:,:)
!~               call mco_iden (time,jcen,nbod,nbig,h0,m,xh,vh,x,v,ngf,ngflag)
           else
              call coord (time,jcen,nbod,nbig,h0,m,xh,vh,x,v,ngf,ngflag)
           end if
        end if
        tfun = time
     end if
     
     ! Go on to the next time step
  end do
  
  !------------------------------------------------------------------------------
  
end subroutine mal_hcon

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

!      MXX_SYNC.FOR    (ErikSoft   2 March 2001)

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

! Author: John E. Chambers

! Synchronizes the epochs of NBIG Big bodies (having a common epoch) and
! NBOD-NBIG Small bodies (possibly having differing epochs), for an 
! integration using MERCURY.
! The Small bodies are picked up in order starting with the one with epoch
! furthest from the time, TSTART, at which the main integration will begin
! producing output.

! N.B. The synchronization integrations use Everhart's RA15 routine.
! ---

!------------------------------------------------------------------------------

subroutine mxx_sync (time,tstart,h0,tol,jcen,nbod,nbig,m,x,v,s,rho,rceh,stat,id,epoch,ngf,ngflag)
  
  use physical_constant
  use mercury_constant

  implicit none

  
  ! Input/Output
  integer :: nbod,nbig,ngflag,stat(nbod)
  real(double_precision) :: time,tstart,h0,tol,jcen(3),m(nbod),x(3,nbod),v(3,nbod)
  real(double_precision) :: s(3,nbod),rceh(nbod),rho(nbod),epoch(nbod),ngf(4,nbod)
  character*8 id(nbod)
  
  ! Local
  integer :: j,k,l,nsml,nsofar,indx(NMAX),itemp,jtemp(NMAX)
  integer :: raflag,nce,ice(NMAX),jce(NMAX)
  real(double_precision) :: temp,epsml(NMAX),rtemp(NMAX)
  real(double_precision) :: h,hdid,tsmall,rphys(NMAX),rcrit(NMAX)
  character*8 ctemp(NMAX)
  
  !------------------------------------------------------------------------------
  
  ! Reorder Small bodies by epoch so that ep(1) is furthest from TSTART
  nsml = nbod - nbig
  do j = nbig + 1, nbod
     epsml(j-nbig) = epoch(j)
  end do
  call mxx_sort (nsml,epsml,indx)
  
  if (abs(epsml(1)-tstart).lt.abs(epsml(nsml)-tstart)) then
     k = nsml + 1
     do j = 1, nsml / 2
        l = k - j
        temp = epsml(j)
        epsml(j) = epsml (l)
        epsml(l) = temp
        itemp = indx(j)
        indx(j) = indx (l)
        indx(l) = itemp
     end do
  end if
  
  do j = nbig + 1, nbod
     epoch(j) = epsml(j-nbig)
  end do
  
  ! Reorder the other arrays associated with each Small body
  do k = 1, 3
     do j = 1, nsml
        rtemp(j) = x(k,j+nbig)
     end do
     do j = 1, nsml
        x(k,j+nbig) = rtemp(indx(j))
     end do
     do j = 1, nsml
        rtemp(j) = v(k,j+nbig)
     end do
     do j = 1, nsml
        v(k,j+nbig) = rtemp(indx(j))
     end do
     do j = 1, nsml
        rtemp(j) = s(k,j+nbig)
     end do
     do j = 1, nsml
        s(k,j+nbig) = rtemp(indx(j))
     end do
  end do
  
  do j = 1, nsml
     rtemp(j) = m(j+nbig)
  end do
  do j = 1, nsml
     m(j+nbig) = rtemp(indx(j))
  end do
  do j = 1, nsml
     rtemp(j) = rceh(j+nbig)
  end do
  do j = 1, nsml
     rceh(j+nbig) = rtemp(indx(j))
  end do
  do j = 1, nsml
     rtemp(j) = rho(j+nbig)
  end do
  do j = 1, nsml
     rho(j+nbig) = rtemp(indx(j))
  end do
  
  do j = 1, nsml
     ctemp(j) = id(j+nbig)
     jtemp(j) = stat(j+nbig)
  end do
  do j = 1, nsml
     id(j+nbig) = ctemp(indx(j))
     stat(j+nbig) = jtemp(indx(j))
  end do
  
  ! Integrate Small bodies up to the same epoch
  h = h0
  tsmall = h0 * 1.d-12
  raflag = 0
  
  do j = nbig + 1, nbod
     nsofar = j - 1
     do while (abs(time-epoch(j)).gt.tsmall)
        temp = epoch(j) - time
        h = sign(max(min(abs(temp),abs(h)),tsmall),temp)
        call mdt_ra15 (time,h,hdid,tol,jcen,nsofar,nbig,m,x,v,s,rphys,rcrit,ngf,stat,raflag,ngflag,nce,ice,jce,mfo_all)
        time = time + hdid
     end do
     raflag = 1
  end do
  
  !------------------------------------------------------------------------------
  
  return
end subroutine mxx_sync

end program mercury


