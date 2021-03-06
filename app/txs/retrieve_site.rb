require_relative '../../lib/assets/geo/geocalc'
require 'geocoder'

class RetrieveSite

  SW = 0
  NE = 1
  LAT = 0
  LONG = 1

  DAYS = 7

  AIRBNB_MAX_PAGES = 56

  # @airbnb_route_areas = []

  def self.run(params)
    sites = []

    # NOTE: Route Areas for each site type should be updated 
    #       In 'get_siteType_sites area' function
    # Add Sites From External Sources

    puts "DEBUG: Getting airbnb sites for #{params[:area]} . . . "

    sites.concat(get_airbnb_sites params[:area]) # Airbnb

    if sites
      {:status => 200, :success? => true, :sites => sites}
    else
      {:status => :not_found, :error => 'airbnb_scrape_failed', :area => JSON.stringify(params) }
    end
  end

  def self.update(params)
    sites = []

    # NOTE: Route Areas for each site type should be updated 
    #       In 'get_siteType_sites area' function
    # Add Sites From External Sources

    puts "DEBUG: Updating airbnb sites for #{params[:area]} . . . "

    sites.concat(update_airbnb_sites params[:area]) # Airbnb

    if sites
      {:status => 200, :success? => true, :sites => sites}
    else
      {:status => :not_found, :error => 'airbnb_scrape_failed', :area => JSON.stringify(params) }
    end
  end

  private

  def self.get_updated(tables, days)
    tables.select do |t|
      # Return All Areas that have been updated within the last week
      t[:updated_at] > DateTime.now - days
    end
  end

  def self.get_outdated(tables, days)
    tables.select do |t|
      # Return All Areas that have NOT been updated within the last week
      t[:updated_at] <= DateTime.now - days
    end
  end

  def self.get_encompassing_routeAreas(area)
    RouteArea.where(
      "sw_latitude <= ? AND sw_longitude <= ? AND " + 
      "ne_latitude >= ? AND ne_longitude >= ?", 
      area[SW][LAT].to_f,
      area[SW][LONG].to_f,
      area[NE][LAT].to_f,
      area[NE][LONG].to_f
    )
  end

  def self.get_neighboring_routeAreas(area)
    areas = []
    box = RetrieveAllSites.build_full_box area
    RouteArea.find_each(batch_size: 1000) do |ra|
      # Check if any four points are within the routeArea (ra)
      [box[:sw], box[:se], box[:ne], box[:ne]].each do |point|
        areas.concat(
          RouteArea.where(
            "sw_latitude <= ? AND sw_longitude <= ? AND " + 
            "ne_latitude >= ? AND ne_longitude >= ?", 
            point[LAT].to_f, point[LONG].to_f, point[LAT].to_f, point[LONG].to_f
          )
        )
      end
    end
    areas.uniq{ |area| area["id"] }
  end

  def self.update_airbnb_sites(routeArea)
    sites = []
    umbrellaAreas = {}
    routeAreas = [routeArea]

    while routeArea = routeAreas.pop()

      area_tables = get_encompassing_routeAreas routeArea

      updatedAreas =  (get_updated area_tables, DAYS).select do |area|
        area[:site_type] == 'Airbnb'
      end

      if (updatedAreas.length > 0)
        # Find all Recently Queried Airbnb Areas within The Area
        area = {
          :sw_latitude =>  routeArea[SW][LAT].to_f,
          :sw_longitude => routeArea[SW][LONG].to_f,
          :ne_latitude =>  routeArea[NE][LAT].to_f,
          :ne_longitude => routeArea[NE][LONG].to_f,
        }
        sites.concat(Site.where(
          "latitude >= ? AND longitude >= ? AND latitude <= ? AND longitude <= ?",
          area[:sw_latitude], area[:sw_longitude], area[:ne_latitude], area[:ne_longitude]
        ))
      else
        pages = Airbnb.get_max_pages routeArea
        if(pages >= AIRBNB_MAX_PAGES)
          # Concat the divided section
          if umbrellaAreas[routeAreas.length].nil?
            umbrellaAreas[routeAreas.length] = [routeArea]
          else
            umbrellaAreas[routeAreas.length].push(routeArea)
          end
          routeAreas.concat( Route::Calculation.divide_area(routeArea) )
        else
          airbnb_sites = Airbnb.retrieve_sites routeArea

          if airbnb_sites.length > 0
            # Add all found Airbnbs to this routeArea
            airbnb_sites.each do |new_airbnb_site|
              old_airbnb_site = Site.where(
                "type = ? AND meta->>'room_id' = ?",
                "Airbnb", new_airbnb_site[:meta][:room_id]
              ).first
              if (entry = build_model_entry new_airbnb_site, Airbnb, old_airbnb_site)
                sites.push(entry)
              end
            end
            new_airbnb_route_area = {
              :sw_latitude =>  routeArea[SW][LAT].to_f,
              :sw_longitude => routeArea[SW][LONG].to_f,
              :ne_latitude =>  routeArea[NE][LAT].to_f,
              :ne_longitude => routeArea[NE][LONG].to_f,
              :site_type => 'Airbnb'
            }
            # Build New Route Area
            build_model_entry new_airbnb_route_area, RouteArea
          end
        end
      end
      if umbrellaAreas[routeAreas.length] && umbrellaAreas[routeAreas.length].length > 0
        umbrellaAreas[routeAreas.length].each do |routeArea|
          new_airbnb_route_area = {
            :sw_latitude =>  routeArea[SW][LAT].to_f,
            :sw_longitude => routeArea[SW][LONG].to_f,
            :ne_latitude =>  routeArea[NE][LAT].to_f,
            :ne_longitude => routeArea[NE][LONG].to_f,
            :site_type => 'Airbnb'
          }
          # Build New Route Area
          build_model_entry new_airbnb_route_area, RouteArea
        end
        umbrellaAreas.delete(routeAreas.length)
      end
    end

    # Destroy all Outdated Areas
    outdatedAreas = (get_outdated area_tables, DAYS).select do |area|
      area[:site_type] == 'Airbnb'
    end
    outdatedAreas.each do |area|
      area.destroy
    end

    # Delete all Entries that have not been updated in a month
    # Site.where("updated_at <= ?", DateTime.now - DAYS*4).find_each do |site|
    #   site.destroy
    # end

    sites.uniq{ |site| site["meta"]["room_id"] }
  end

  def self.get_airbnb_sites(routeArea)

    # Find all Recently Queried Airbnb Areas within The Area
    area = {
      :sw_latitude =>  routeArea[SW][LAT].to_f,
      :sw_longitude => routeArea[SW][LONG].to_f,
      :ne_latitude =>  routeArea[NE][LAT].to_f,
      :ne_longitude => routeArea[NE][LONG].to_f,
    }
    Site.where(
      "latitude >= ? AND longitude >= ? AND latitude <= ? AND longitude <= ?",
      area[:sw_latitude], area[:sw_longitude], area[:ne_latitude], area[:ne_longitude]
    )
  end

  def self.build_model_entry new_site, model, old_site = nil
    if(old_site)
      # Update Existing Model Entry
      if (old_site[:updated_at] <= DateTime.now - DAYS)
        # Update the Found Outdated Site
        old_site.update!(new_site)
      else
        old_site
      end
    else
      # Create New Model Entry
      model.create!(new_site)
    end
  end

end

# sites.length
# sites = Site.where(type: 'Airbnb').as_json
# sites.length
# sites.uniq{ |site| site.["meta"]["room_id"] }.length