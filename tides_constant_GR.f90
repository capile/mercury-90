module tides_constant_GR
  use types_numeriques

  implicit none
  !
  ! Author: Emeline Bolmont
  ! Date: 04/04/13
  !
  ! If you want Tides or not
  integer, parameter :: tides=1
  ! If you want General Relativity or not
  integer, parameter :: GenRel=1
  ! Number of tidally evolving planets
  integer, parameter :: ntid=2
  ! Nature of host body
  integer, parameter :: brown_dwarf=1
  integer, parameter :: M_dwarf=0
  integer, parameter :: Sun_like_star=0  
  integer, parameter :: Jupiter_host=0  
  ! For an utilization of the code with no changing host body
  integer, parameter :: Rscst=0 !=1 : Rs = cst, rg2s = cst
  real(double_precision), parameter :: Rjup = 10.9d0 !rearth	
  
  ! Integration stuff
  real(double_precision), parameter :: t_init = 1.d6*365.25!1.0d6*365.25
  ! If crash, write last line of spin.dat here : 
  integer, parameter :: crash=0
  real(double_precision), parameter :: t_crash = 0.0d0*365.25!1.0d6*365.25
  real(double_precision), parameter, dimension(3) :: rot_crash  = (/0.0,0.0,0.0/)
  real(double_precision), parameter, dimension(3) :: rot_crashp1 = (/0.0,0.0,0.0/)
  real(double_precision), parameter, dimension(3) :: rot_crashp2 = (/0.0,0.0,0.0/)
  real(double_precision), parameter, dimension(3) :: rot_crashp3 = (/0.0,0.0,0.0/)
  real(double_precision), parameter, dimension(3) :: rot_crashp4 = (/0.0,0.0,0.0/)
  real(double_precision), parameter, dimension(3) :: rot_crashp5 = (/0.0,0.0,0.0/)
  real(double_precision), parameter, dimension(3) :: rot_crashp6 = (/0.0,0.0,0.0/)

  ! Planet dissipation, and caracteristics
  
  ! If pseudo_rot eq 0 : initial period as given by Pp0 (in hr)
  ! If pseudo_rot eq toto : initial period = toto*pseudo_synchronization period 
  real(double_precision), parameter, dimension(ntid) :: pseudo_rot = (/1.d0,1.d0/)
  real(double_precision), parameter, dimension(ntid) :: Pp0 = (/24.d0, 24.d0/) 	
  real(double_precision), parameter, dimension(ntid) :: dissplan = (/1.d0,10.d0/)
  ! Planets obliquities in rad
  real(double_precision), parameter, dimension(ntid) :: oblp = (/0.0d0,0.0d0/)				
  
  ! Indicate if Planet is of known parameters.
  ! 0: Earth-like, 1: Terrestrial (no mass-radius relationship), 2: Gas giant
  ! 3: others (like Neptune)
  integer, parameter, dimension(ntid) :: jupiter = (/0,0/)
  ! If jupiter ne 0, then indicate radius in Rearth, for ex: 1 or 0.954d0*Rjup
  real(double_precision), parameter, dimension(ntid) :: radius_p = (/0.d0,0.d0/)
  ! Radius of gyration, love number and k2delta_t for other planets (jupiter=3)
  real(double_precision), parameter :: rg2p_what = 3.308d-1
  real(double_precision), parameter :: k2p_what = 0.305d0
  real(double_precision), parameter :: k2pdeltap_what = 2.465278d-3
  
  ! Star dissipation, and caracteristics in CGS
  real(double_precision), parameter :: dissstar = 1.0d0!1.0d0!1.d2
  
  ! Dissipation factors of allowed host body
  
  ! For R=cst, choose sigmast:
  real(double_precision), parameter :: sigma_what = 2.006*3.845764d4 !-60+64
  real(double_precision), parameter :: rg2_what = 2.0d-1
  real(double_precision), parameter :: k2st_what = 0.307d0 
  ! For R=cst, or dM or Suns
  real(double_precision), parameter :: Period_st   = 8.0d0    !day
  real(double_precision), parameter :: radius_star = 0.943 !Rsun
 
  
  !*********************************************************************
  !*********************************************************************
  ! No Need to chang stuff from here
  ! Radius of gyration and love number for dM 
  real(double_precision), parameter :: rg2_dM = 2.0d-1
  real(double_precision), parameter :: k2st_dM = 0.307d0 
  ! Radius of gyration and love number for Suns
  real(double_precision), parameter :: rg2_Sun = 5.9d-2
  real(double_precision), parameter :: k2st_Sun = 0.03d0 
  ! Radius of gyration, love number and k2delta_t for terrestrial planets
  real(double_precision), parameter :: rg2p_terr = 3.308d-1
  real(double_precision), parameter :: k2p_terr = 0.305d0
  real(double_precision), parameter :: k2pdeltap_terr = 2.465278d-3
  ! Radius of gyration, love number and k2delta_t for gas giants
  real(double_precision), parameter :: rg2p_gg = 2.54d-1
  real(double_precision), parameter :: k2p_gg = 0.38d0
  real(double_precision), parameter :: k2pdeltap_gg = 8.101852d-9
 
  ! Sigma for BD, dM, Suns, Jupiter
  ! BD, Mdwarf: sigmast = 2.006d-60 cgs, conversion to Msun-1.AU-2.day-1 = 3.845764022293d64
  real(double_precision), parameter :: sigma_BD = 2.006*3.845764d4 !-60+64
  real(double_precision), parameter :: sigma_dM = 2.006*3.845764d4 !-60+64
  ! Sun-like-star: sigmast = 4.992d-66 cgs, conversion to Msun-1.AU-2.day-1 = 3.845764022293d64
  real(double_precision), parameter :: sigma_Sun = 4.992*3.845764d-2 !-66+64
  ! If planet not terrestrial, dissipation factor Hot Gas Giant
  real(double_precision), parameter :: sigma_gg = 2.006*3.845764d4
  ! k2delta_t for Jupiter: 2-3d-2 s, here in day
  real(double_precision), parameter :: k2delta_jup = 2.893519d-7
  
  ! Some stuff, constants mainly
  real(double_precision), parameter :: rsun = 4.67920694d-3
  real(double_precision), parameter :: rearth = 4.25874677d-5
  real(double_precision), parameter :: m2earth = (1.9891d6/5.9794)
  ! meter in AU
  real(double_precision), parameter :: minau = 6.68458d-12
  ! Speed of light
  real(double_precision), parameter :: C2 = 1.731444830225d2

contains 

  function get_initial_timestep()
    ! function that return the initial timestep of the simulation

    use utilities, only : mio_spl

    implicit none

    !Input
    !None actually

    ! Outpout
    real(double_precision), dimension(2) :: get_initial_timestep ! the timestep of the simulation as writed in param.in

    !Locals
    integer :: j, lineno, nsub, lim(2,10), error
    real(double_precision) :: h0,tstop
    character(len=80) :: c80
    character(len=150) :: string


    open(13, file='param.in', status='old', iostat=error)
    if (error /= 0) then
       write (*,'(/,2a)') " ERROR: Programme terminated. Unable to open ",trim('param.in')
       stop
    end if
    ! Read integration parameters
    lineno = 0
    do j = 1, 26
       ! We want the next non commented line
       do
          lineno = lineno + 1
          read (13,'(a150)') string
          if (string(1:1).ne.')') exit
       end do

       call mio_spl (150,string,nsub,lim)
       c80(1:3) = '   '
       c80 = string(lim(1,nsub):lim(2,nsub))

       if (j.eq.3) read (c80,*) tstop
       if (j.eq.5) read (c80,*) h0
    end do
    get_initial_timestep = (/tstop,abs(h0)/)

    close (13)
    return
  end function get_initial_timestep

subroutine write_simus_properties()
! subroutine that write the parameters of the user_module into the file 'tidesGR.out'

  use git_infos

  implicit none
  
  real(double_precision), dimension(2) :: timestep
  real(double_precision) :: distance_accuracy
  integer :: j
  real(double_precision), parameter :: TWOTHIRD = 2.d0 / 3.d0
  
  
  timestep = get_initial_timestep()
  ! below this limit, with this timestep, an orbit will only contain 10 timestep or less, whiis not accurate.
  distance_accuracy = (10. * timestep(2) / 365.25)**TWOTHIRD 
  
  open(10, file='tidesGR.out')

  write(10,'(a)') '------------------------------------'
  write(10,'(a)') '|         Timestep stuff           |'
  write(10,'(a)') '------------------------------------'
  write(10,'(a,f8.4,a)') 'timestep = ',timestep(2), ' days'
  write(10,'(a,f8.4,a)') '  with this timestep, the simulation will not be accurate below', distance_accuracy, ' AU'
  write(10,'(a)') '------------------------------------'
  write(10,'(a)') '|       Mercury Properties         |'
  write(10,'(a)') '------------------------------------'
  write(10,'(a,a)') 'branch = ', branch
  write(10,'(a,a)') 'commit = ', commit
  write(10,'(a,a)') 'tags = ', tags
  write(10,'(a)') modifs
  write(10,'(a,f8.4,a,f8.4,a)') 'With h=', timestep(2), ' days, the simulation will be accurate for r > ', distance_accuracy, ' AU'
  write(10,'(a)') '------------------------------------'
  write(10,'(a)') '|       Special Effects            |'
  write(10,'(a)') '------------------------------------'
  if (tides.eq.1) write(10,'(a)') 'Tides are on'
  if (GenRel.eq.1) write(10,'(a)') 'General Relativity effects taken into account'
  if (brown_dwarf.eq.1) write(10,'(a)') 'The central body is an evolving Brown-dwarf'
  if (M_dwarf.eq.1) write(10,'(a)') 'The central body is an evolving M-dwarf'
  if (Sun_like_star.eq.1) write(10,'(a)') 'The central body is an evolving Sun-like star'
  if (Rscst.eq.1) write(10,'(a)') 'The central body is an non-evolving object'
  write(10,*) ''
  if (tides.eq.1) then
     write(10,'(a,i1)') 'Number of planets tidally evolving =',ntid
     do j = 1, ntid
        write(10,'(a,i1)') 'PLANET',j
        if ((jupiter(j-1).eq.0).or.(jupiter(j-1).eq.1)) then
           write(10,'(a,f8.4,a,f8.4)') 'k2p =',k2p_terr,', rg2p =',rg2p_terr
           write(10,'(a,f8.4,a,f8.4)') 'k2pdeltap =',k2pdeltap_terr,' day, dissplan =',dissplan(j)     
        endif
        if (jupiter(j-1).eq.2) then
           write(10,'(a,f8.4,a,f8.4)') 'k2p =',k2p_gg,', rg2p =',rg2p_gg
           write(10,'(a,f8.4,a,f8.4)') 'k2pdeltap =',k2pdeltap_gg,' day, dissplan =',dissplan(j)   
        endif
        if (jupiter(j-1).eq.3) then
           write(10,'(a,f8.4,a,f8.4)') 'k2p =',k2p_what,', rg2p =',rg2p_what
           write(10,'(a,f8.4,a,f8.4)') 'k2pdeltap =',k2pdeltap_what,' day, dissplan =',dissplan(j)
        endif
     enddo
  endif
  write(10,*) ''
  close(10)
  
end subroutine write_simus_properties

end module tides_constant_GR
