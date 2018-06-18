module mo_grid
  use mo_kind, only : dp, i4

  IMPLICIT NONE

  PRIVATE

  PUBLIC :: init_lowres_level, set_basin_indices, L0_grid_setup, &
          mapCoordinates, geoCoordinates
contains
  ! ------------------------------------------------------------------

  !      NAME
  !         L1_variable_init

  !>        \brief Level-1 variable initialization

  !>        \details following tasks are performed for L1 datasets
  !>                 -  cell id & numbering
  !>                 -  mask creation
  !>                 -  storage of cell cordinates (row and coloum id)
  !>                 -  sorage of four corner L0 cordinates
  !>                 If a variable is added or removed here, then it also has to
  !>                 be added or removed in the subroutine config_variables_set in
  !>                 module mo_restart and in the subroutine set_config in module
  !>                 mo_set_netcdf_restart

  !     INTENT(IN)
  !>        \param[in] "integer(i4)       ::  iBasin"               basin id

  !     INTENT(INOUT)
  !         None

  !     INTENT(OUT)
  !         None

  !     INTENT(IN), OPTIONAL
  !         None

  !     INTENT(INOUT), OPTIONAL
  !         None

  !     INTENT(OUT), OPTIONAL
  !         None

  !     RETURN
  !         None

  !     RESTRICTIONS
  !         None

  !     EXAMPLE
  !         None

  !     LITERATURE
  !         None

  !     HISTORY
  !         \author  Rohini Kumar
  !         \date    Jan 2013

  subroutine init_lowres_level(highres, target_resolution, lowres, highres_lowres_remap)

    use mo_common_variables, only : &
            Grid, GridRemapper
    use mo_common_constants, only : nodata_dp, nodata_i4

    implicit none

    type(Grid), target, intent(in) :: highres
    real(dp), intent(in) :: target_resolution
    type(Grid), target, intent(inout) :: lowres
    type(GridRemapper), intent(inout), optional :: highres_lowres_remap

    ! local variables
    real(dp), dimension(:, :), allocatable :: areaCell0_2D

    real(dp) :: cellFactor

    integer(i4) :: iup, idown
    integer(i4) :: jl, jr

    integer(i4) :: i, j, k, ic, jc

    !--------------------------------------------------------
    ! STEPS::
    ! 1) Estimate each variable locally for a given basin
    ! 2) Pad each variable to its corresponding global one
    !--------------------------------------------------------

    ! grid properties
    if (.not. allocated(lowres%mask)) then
      call calculate_grid_properties(highres%nrows, highres%ncols, &
              highres%xllcorner, highres%yllcorner, highres%cellsize, &
              target_resolution, &
              lowres%nrows, lowres%ncols, &
              lowres%xllcorner, lowres%yllcorner, lowres%cellsize)
      ! cellfactor = leve1-1 / level-0
      cellFactor = lowres%cellsize / highres%cellsize

      ! allocation and initalization of mask at level-1
      allocate(lowres%mask(lowres%nrows, lowres%ncols))
      lowres%mask(:, :) = .FALSE.

      ! create mask at level-1
      do j = 1, highres%ncols
        jc = ceiling(real(j, dp) / cellFactor)
        do i = 1, highres%nrows
          if (.NOT. highres%mask(i, j)) cycle
          ic = ceiling(real(i, dp) / cellFactor)
          lowres%mask(ic, jc) = .TRUE.
        end do
      end do

      ! estimate ncells and initalize related variables
      lowres%nCells = count(lowres%mask)
      ! allocate and initalize cell1 related variables
      allocate(lowres%Id        (lowres%nCells))
      lowres%Id = (/ (k, k = 1, lowres%nCells) /)
    end if

    if (present(highres_lowres_remap)) then
      ! cellfactor = leve1-1 / level-0, set again in case not yet initialized
      cellFactor = lowres%cellsize / highres%cellsize

      ! lowres additional properties
      allocate(areaCell0_2D(highres%nrows, highres%ncols))
      areaCell0_2D(:, :) = UNPACK(highres%CellArea, highres%mask, nodata_dp)

      if (.not. allocated(lowres%CellCoor)) then
        allocate(lowres%CellCoor  (lowres%nCells, 2))
        allocate(lowres%CellArea  (lowres%nCells))
      end if

      allocate(highres_lowres_remap%lower_bound(lowres%nCells))
      allocate(highres_lowres_remap%upper_bound(lowres%nCells))
      allocate(highres_lowres_remap%left_bound (lowres%nCells))
      allocate(highres_lowres_remap%right_bound(lowres%nCells))
      allocate(highres_lowres_remap%n_subcells (lowres%nCells))
      allocate(highres_lowres_remap%lowres_id_on_highres (highres%nrows, highres%ncols))
      highres_lowres_remap%lowres_id_on_highres = nodata_i4

      highres_lowres_remap%high_res_grid => highres
      highres_lowres_remap%low_res_grid => lowres

      k = 0
      do jc = 1, lowres%ncols
        do ic = 1, lowres%nrows
          if (.NOT. lowres%mask(ic, jc)) cycle
          k = k + 1

          lowres%CellCoor(k, 1) = ic
          lowres%CellCoor(k, 2) = jc

          ! coord. of all corners -> of finer scale level-0
          iup = (ic - 1) * nint(cellFactor, i4) + 1
          idown = ic * nint(cellFactor, i4)
          jl = (jc - 1) * nint(cellFactor, i4) + 1
          jr = jc * nint(cellFactor, i4)

          ! constrain the range of up, down, left, and right boundaries
          if(iup   < 1) iup = 1
          if(idown > highres%nrows) idown = highres%nrows
          if(jl    < 1) jl = 1
          if(jr    > highres%ncols) jr = highres%ncols

          highres_lowres_remap%upper_bound   (k) = iup
          highres_lowres_remap%lower_bound (k) = idown
          highres_lowres_remap%left_bound (k) = jl
          highres_lowres_remap%right_bound(k) = jr

          ! effective area [km2] & total no. of L0 cells within a given L1 cell
          lowres%CellArea(k) = sum(areacell0_2D(iup : idown, jl : jr), highres%mask(iup : idown, jl : jr))
          highres_lowres_remap%n_subcells(k) = count(highres%mask(iup : idown, jl : jr))
          ! Delimitation of level-11 cells on level-0
          highres_lowres_remap%lowres_id_on_highres(iup : idown, jl : jr) = k
        end do
      end do

      ! free space
      deallocate(areaCell0_2D)

    end if

  end subroutine init_lowres_level

  subroutine set_basin_indices(grids)
    ! this is separate because the Grid initialization is usually called within a basin loop...

    use mo_common_variables, only : Grid
    implicit none

    type(Grid), intent(inout), dimension(:) :: grids

    ! local variables
    integer(i4) :: iBasin

    do iBasin = 1, size(grids)
      ! Saving indices of mask and packed data
      if(iBasin .eq. 1_i4) then
        grids(iBasin)%iStart = 1_i4
      else
        grids(iBasin)%iStart = grids(iBasin - 1_i4)%iEnd + 1_i4
      end if
      grids(iBasin)%iEnd = grids(iBasin)%iStart + grids(iBasin)%nCells - 1_i4
    end do

  end subroutine set_basin_indices

  ! ------------------------------------------------------------------

  !      NAME
  !          L0_variable_init

  !>        \brief   level 0 variable initialization

  !>        \details following tasks are performed for L0 data sets
  !>                 -  cell id & numbering
  !>                 -  storage of cell cordinates (row and coloum id)
  !>                 -  empirical dist. of terrain slope
  !>                 -  flag to determine the presence of a particular soil id
  !>                    in this configuration of the model run
  !>                 If a variable is added or removed here, then it also has to
  !>                 be added or removed in the subroutine config_variables_set in
  !>                 module mo_restart and in the subroutine set_config in module
  !>                 mo_set_netcdf_restart

  !     INTENT(IN)
  !>        \param[in] "integer(i4)               :: iBasin"  basin id

  !     INTENT(INOUT)
  !>        \param[in,out] "integer(i4), dimension(:) :: soilId_isPresent"
  !>        flag to indicate wether a given soil-id is present or not, DIMENSION [nSoilTypes]

  !     INTENT(OUT)
  !         None

  !     INTENT(IN), OPTIONAL
  !         None

  !     INTENT(INOUT), OPTIONAL
  !         None

  !     INTENT(OUT), OPTIONAL
  !         None

  !     RETURN
  !         None

  !     RESTRICTIONS
  !         None

  !     EXAMPLE
  !         None

  !     LITERATURE
  !         None

  !     HISTORY
  !         \author  Rohini Kumar
  !         \date    Jan 2013
  !         Modified
  !         Rohini Kumar & Matthias Cuntz,  May 2014 - cell area calulation based on a regular lat-lon grid or
  !                                                    on a regular X-Y coordinate system
  !         Matthias Cuntz,                 May 2014 - changed empirical distribution function
  !                                                    so that doubles get the same value
  !         Matthias Zink & Matthias Cuntz, Feb 2016 - code speed up due to reformulation of CDF calculation
  !                           Rohini Kumar, Mar 2016 - changes for handling multiple soil database options

  subroutine L0_grid_setup(new_grid)

    use mo_common_variables, only : Grid, iFlag_cordinate_sys
    use mo_constants, only : TWOPI_dp, RadiusEarth_dp

    implicit none

    type(Grid), intent(inout) :: new_grid

    ! local variables
    real(dp), dimension(:, :), allocatable :: areaCell_2D

    integer(i4) :: i, j, k
    real(dp) :: rdum, degree_to_radian, degree_to_metre

    !--------------------------------------------------------
    ! STEPS::
    ! 1) Estimate each variable locally for a given basin
    ! 2) Pad each variable to its corresponding global one
    !--------------------------------------------------------

    ! level-0 information
    new_grid%nCells = count(new_grid%mask)

    allocate(new_grid%CellCoor(new_grid%nCells, 2))
    allocate(new_grid%Id(new_grid%nCells))
    allocate(new_grid%CellArea(new_grid%nCells))
    allocate(areaCell_2D(new_grid%nrows, new_grid%ncols))

    new_grid%Id = (/ (k, k = 1, new_grid%nCells) /)

    !------------------------------------------------
    ! start looping for cell cordinates and ids
    !------------------------------------------------
    k = 0
    do j = 1, new_grid%ncols
      do i = 1, new_grid%nrows
        if (.NOT. new_grid%mask(i, j)) cycle
        k = k + 1
        new_grid%cellCoor(k, 1) = i
        new_grid%cellCoor(k, 2) = j
      end do
    end do

    ! ESTIMATE AREA [m2]

    ! regular X-Y coordinate system
    if(iFlag_cordinate_sys .eq. 0) then
      new_grid%CellArea(:) = new_grid%cellsize * new_grid%cellsize

      ! regular lat-lon coordinate system
    else if(iFlag_cordinate_sys .eq. 1) then

      degree_to_radian = TWOPI_dp / 360.0_dp
      degree_to_metre = RadiusEarth_dp * TWOPI_dp / 360.0_dp
      do i = new_grid%ncols, 1, -1
        j = new_grid%ncols - i + 1
        ! get latitude in degrees
        rdum = new_grid%yllcorner + (real(j, dp) - 0.5_dp) * new_grid%cellsize
        ! convert to radians
        rdum = rdum * degree_to_radian
        !    AREA [m2]
        areaCell_2D(:, i) = (new_grid%cellsize * cos(rdum) * degree_to_metre) * (new_grid%cellsize * degree_to_metre)
      end do
      new_grid%CellArea(:) = pack(areaCell_2D(:, :), new_grid%mask)

    end if

    ! free space
    deallocate(areaCell_2D)

  end subroutine L0_grid_setup


  !------------------------------------------------------------------
  !     NAME
  !         mapCoordinates
  !
  !     PURPOSE
  !>        \brief Generate map coordinates
  !>        \details Generate map coordinate arrays for given basin and level
  !
  !     CALLING SEQUENCE
  !         call mapCoordinates(ibasin, level, y, x)
  !
  !     INTENT(IN)
  !>        \param[in] "integer(i4)      :: iBasin" -> basin number
  !>        \param[in] "type(geoGridRef) :: level"  -> grid reference
  !
  !     INTENT(INOUT)
  !         None
  !
  !     INTENT(OUT)
  !>        \param[out] "real(:)  :: y(:)"          -> y-coordinates
  !>        \param[out] "real(dp) :: x(:)"          -> x-coorindates
  !
  !     INTENT(IN), OPTIONAL
  !         None
  !
  !     INTENT(INOUT), OPTIONAL
  !         None
  !
  !     INTENT(OUT), OPTIONAL
  !         None
  !
  !     RETURN
  !         None
  !
  !     RESTRICTIONS
  !         None
  !
  !     EXAMPLE
  !         None
  !
  !     LITERATURE
  !         None
  !
  !     HISTORY
  !>        \author Matthias Zink
  !>        \date Apr 2013
  !         Modified:
  !             Stephan Thober, Nov 2013 - removed fproj dependency
  !             David Schaefer, Jun 2015 - refactored the former subroutine CoordSystem
  subroutine mapCoordinates(level, y, x)

    use mo_common_variables, only : Grid

    implicit none

    type(Grid), intent(in) :: level
    real(dp), intent(out), allocatable :: x(:), y(:)
    integer(i4) :: ii, ncols, nrows
    real(dp) :: cellsize

    cellsize = level%cellsize
    nrows = level%nrows
    ncols = level%ncols

    allocate(x(nrows), y(ncols))

    x(1) = level%xllcorner + 0.5_dp * cellsize
    do ii = 2, nrows
      x(ii) = x(ii - 1) + cellsize
    end do

    ! inverse for Panoply, ncview display
    y(ncols) = level%yllcorner + 0.5_dp * cellsize
    do ii = ncols - 1, 1, -1
      y(ii) = y(ii + 1) + cellsize
    end do

  end subroutine mapCoordinates

  !------------------------------------------------------------------
  !     NAME
  !         geoCoordinates
  !
  !     PURPOSE
  !>        \brief Generate geographic coordinates
  !>        \details Generate geographic coordinate arrays for given basin and level
  !
  !     CALLING SEQUENCE
  !         call mapCoordinates(ibasin, level, y, x)
  !
  !     INTENT(IN)
  !>        \param[in] "integer(i4)      :: iBasin"    -> basin number
  !>        \param[in] "type(Grid) :: level"     -> grid reference
  !
  !     INTENT(INOUT)
  !         None
  !
  !     INTENT(OUT)
  !>        \param[out] "real(dp) :: lat(:,:)"         -> lat-coordinates
  !>        \param[out] "real(dp) :: lon(:,:)"         -> lon-coorindates
  !
  !     INTENT(IN), OPTIONAL
  !         None
  !
  !     INTENT(INOUT), OPTIONAL
  !         None
  !
  !     INTENT(OUT), OPTIONAL
  !         None
  !
  !     RETURN
  !         None
  !
  !     RESTRICTIONS
  !         None
  !
  !     EXAMPLE
  !         None
  !
  !     LITERATURE
  !         None
  !
  !     HISTORY
  !>        \author Matthias Zink
  !>        \date Apr 2013
  !         Modified:
  !             Stephan Thober, Nov 2013 - removed fproj dependency
  !             David Schaefer, Jun 2015 - refactored the former subroutine CoordSystem
  !             Stephan Thober, Sep 2015 - using mask to unpack coordinates
  !             Stephan Thober, Oct 2015 - writing full lat/lon again
  subroutine geoCoordinates(level, lat, lon)

    use mo_common_variables, only : Grid

    implicit none

    type(Grid), intent(in) :: level
    real(dp), intent(out), allocatable :: lat(:, :), lon(:, :)

    lat = level%y
    lon = level%x

  end subroutine geoCoordinates

  ! ------------------------------------------------------------------

  !      NAME
  !         calculate_grid_properties

  !     PURPOSE
  !>        \brief Calculates basic grid properties at a required coarser level using
  !>              information of a given finer level.

  !>        \brief Calculates basic grid properties at a required coarser level (e.g., L11) using
  !>              information of a given finer level (e.g., L0). Basic grid properties such as
  !>              nrows, ncols, xllcorner, yllcorner cellsize are estimated in this
  !>              routine.

  !     CALLING SEQUENCE
  !         call calculate_grid_properties( nrowsIn, ncolsIn,  xllcornerIn,                     &
  !                                         yllcornerIn,  cellsizeIn, nodata_valueIn,           &
  !                                         aimingResolution, nrowsOut, ncolsOut, xllcornerOut, &
  !                                         yllcornerOut, cellsizeOut, nodata_valueOut )
  !     INTENT(IN)
  !>        \param[in] "integer(i4)             :: nrowsIn"           no. of rows at an input level
  !>        \param[in] "integer(i4)             :: ncolsIn"           no. of cols at an input level
  !>        \param[in] "real(dp)                :: xllcornerIn"       xllcorner at an input level
  !>        \param[in] "real(dp)                :: yllcornerIn"       yllcorner at an input level
  !>        \param[in] "real(dp)                :: cellsizeIn"        cell size at an input level
  !>        \param[in] "real(dp)                :: nodata_valueIn"    nodata value at an input level
  !>        \param[in] "real(dp)                :: aimingResolution"  resolution of an output level

  !     INTENT(INOUT)
  !         None

  !     INTENT(OUT)
  !>        \param[out] "integer(i4)             :: nrowsOut"         no. of rows at an output level
  !>        \param[out] "integer(i4)             :: ncolsOut"         no. of cols at an output level
  !>        \param[out] "real(dp)                :: xllcornerOut"      xllcorner at an output level
  !>        \param[out] "real(dp)                :: yllcornerOut"      yllcorner at an output level
  !>        \param[out] "real(dp)                :: cellsizeOut"       cell size at an output level
  !>        \param[out] "real(dp)                :: nodata_valueOut"   nodata value at an output level

  !     INTENT(IN), OPTIONAL
  !         None

  !     INTENT(INOUT), OPTIONAL
  !         None

  !     INTENT(OUT), OPTIONAL
  !         None

  !     RETURN
  !         None

  !     RESTRICTIONS
  !>       \note resolutions of input and output levels should confirm each other.

  !     EXAMPLE
  !         None

  !     LITERATURE
  !         None

  !     HISTORY
  !>        \author Matthias Zink & Rohini Kumar
  !>        \date Feb 2013
  !         Modified, R. Kumar, Sep 2013   - documentation added according to the template

  subroutine calculate_grid_properties(&
          nrowsIn, ncolsIn, xllcornerIn, yllcornerIn, cellsizeIn, &
          aimingResolution, &
          nrowsOut, ncolsOut, xllcornerOut, yllcornerOut, cellsizeOut)

    use mo_message, only : message       ! for print out
    use mo_string_utils, only : num2str

    implicit none

    integer(i4), intent(in) :: nrowsIn
    integer(i4), intent(in) :: ncolsIn
    real(dp), intent(in) :: xllcornerIn
    real(dp), intent(in) :: yllcornerIn
    real(dp), intent(in) :: cellsizeIn
    real(dp), intent(in) :: aimingResolution

    integer(i4), intent(out) :: nrowsOut
    integer(i4), intent(out) :: ncolsOut
    real(dp), intent(out) :: xllcornerOut
    real(dp), intent(out) :: yllcornerOut
    real(dp), intent(out) :: cellsizeOut

    ! local variables
    real(dp) :: cellfactor

    cellFactor = aimingResolution / cellsizeIn

    if (nint(mod(aimingResolution, cellsizeIn)) /= 0) then
      call message()
      call message('***ERROR: Two resolutions size do not confirm: ', &
              trim(adjustl(num2str(nint(AimingResolution)))), &
              trim(adjustl(num2str(nint(cellsizeIn)))))
      stop 1
    end if

    cellsizeOut = cellsizeIn * cellFactor
    ncolsOut = ceiling(real(ncolsIn, dp) / cellFactor)
    nrowsOut = ceiling(real(nrowsIn, dp) / cellFactor)
    xllcornerOut = xllcornerIn + real(ncolsIn, dp) * cellsizeIn - real(ncolsOut, dp) * cellsizeOut
    yllcornerOut = yllcornerIn + real(nrowsIn, dp) * cellsizeIn - real(nrowsOut, dp) * cellsizeOut

  end subroutine calculate_grid_properties

end module mo_grid