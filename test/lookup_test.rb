require 'active_record'
$:.push File.expand_path('lib')
#$:.push File.expand_path('../lib', __FILE__)
require 'rails_lookup'
require 'minitest/autorun'
require '20110808002412_create_test_lookup_db'

# It sucks we have to do that in testing code, but I have to establish a
# connection prior to defining any classes that use lookups, and I see no other
# way around it other than extracting the test classes and requiring them only
# after the connection is established in setup() - which might be a nice
# solution but muddles things up.
# Establish a connection to the test database:
conn = ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", 
  database: "test/test.sqlite3",
  pool: 5,
  timeout: 5000
)
puts "Established connection!" unless conn.nil?
begin
  CreateTestLookupDb.migrate(:down) # Connection has to be established for this to work
rescue
end
CreateTestLookupDb.migrate(:up)

class Car < ActiveRecord::Base
  include RailsLookup
  lookup :car_kind, :as => :kind
  lookup :car_color, :as => :color

  # Example of how to scope for lookups
  scope :by_color, lambda { |color| 
    joins(:car_color)\
      .where({:car_colors => { name: color }})
  }
end

class Plane < ActiveRecord::Base
  include RailsLookup
  lookup :plane_kind, :as => :kind
end

class Spaceship < ActiveRecord::Base
  include RailsLookup
  lookup :cargo, :presence => false
end

class LookupTest < MiniTest::Unit::TestCase

  def setup
    clear_tables
  end

  def teardown
    clear_tables
  end

  def clear_tables
    # In every test you ever do, these calls will be required for all lookup
    # tables involved, since they take care of clearing the (static) caches.
    # Otherwise, you'd have a stale cache in the lookup class.
    Car.delete_all
    CarKind.delete_all
    CarColor.delete_all
    Plane.delete_all
    PlaneKind.delete_all
  end

  def test_initializers
    assert_equal 0, CarKind.count
    assert_equal 0, CarColor.count
    bimba = Car.new(:name => "Bimba", :kind => "Compact", :color => "Yellow")
    assert_equal "Yellow", bimba.color
    assert_equal "Compact", bimba.kind
    assert_equal "Bimba", bimba.name
    assert_equal 1, CarKind.count
    assert_equal 1, CarColor.count
    ferrari = Car.new(:kind => "Sports", :color => "Yellow")
    assert_equal "Yellow", ferrari.color
    assert_equal "Sports", ferrari.kind
    refute(ferrari == bimba)
    assert_equal bimba.color_id, ferrari.color_id
    refute_equal bimba.kind_id, ferrari.kind_id
    assert_equal 2, CarKind.count
    assert_equal 1, CarColor.count
    f16 = Plane.new(:name => "F-16", :kind => "Fighter Jet")
    assert_equal "Fighter Jet", f16.kind
    assert_equal 1, PlaneKind.count
  end

  def test_saving_and_creating
    bimba = Car.new(:name => "Bimba", :kind => "Compact", :color => "Yellow")
    assert_equal "Yellow", bimba.color
    assert_equal "Compact", bimba.kind
    assert_equal "Bimba", bimba.name
    bimba.save!
    bimba_reloaded = Car.all.first
    assert_equal "Yellow", bimba_reloaded.color
    assert_equal "Compact", bimba_reloaded.kind
    assert_equal "Bimba", bimba_reloaded.name
    ferrari = Car.create!(:kind => "Sports", :color => "Yellow")
    assert_equal "Yellow", ferrari.color
    assert_equal "Sports", ferrari.kind
    ferrari_reloaded = Car.all.last
    assert_equal "Yellow", ferrari_reloaded.color
    assert_equal "Sports", ferrari_reloaded.kind
    empty_spaceship = Spaceship.create!(:name => "Nautilus")
    assert_equal nil, empty_spaceship.cargo
    unloaded_spaceship = Spaceship.create!(:name => "Event Horizon", :cargo => "Black Matter")
    assert_equal "Black Matter", unloaded_spaceship.cargo
    unloaded_spaceship.cargo= nil
    assert_equal nil, unloaded_spaceship.cargo
  end

  def test_string_setting_and_getting
    bimba = Car.new
    ferrari = Car.new
    assert_equal 0, CarKind.count
    assert_equal 0, CarColor.count
    bimba.color = "Yellow"
    bimba.name = "Bimba"
    bimba.kind = "Compact"
    assert_equal "Yellow", bimba.color
    assert_equal "Compact", bimba.kind
    assert_equal "Bimba", bimba.name
    assert_equal 1, CarKind.count
    assert_equal 1, CarColor.count
    ferrari.color = "Yellow"
    ferrari.kind = "Sports"
    assert_equal "Yellow", ferrari.color
    assert_equal "Sports", ferrari.kind
    assert_equal bimba.color_id, ferrari.color_id
    refute_equal bimba.kind_id, ferrari.kind_id
    assert_equal 2, CarKind.count
    assert_equal 1, CarColor.count
    bimba.color = "Red"
    assert_equal 2, CarColor.count
    assert_equal "Red", bimba.color
    refute(bimba.color == ferrari.color)
    bimba.color_id = ferrari.color_id #Set via the property_id
    assert_equal "Yellow", bimba.color
  end

  def test_id_for_name_for
    bimba = Car.new
    assert_nil CarKind.id_for("Compact")
    assert_nil CarKind.name_for(1)
    bimba.kind = "Compact"
    assert_equal bimba.kind_id, CarKind.id_for("Compact")
    assert_equal "Compact", CarKind.name_for(bimba.kind_id)
  end

  def test_find_by
    bimba = Car.create! :name => "Bimba", :kind => "Compact", :color => "Yellow"
    ferrari = Car.create! :kind => "Sports", :color => "Yellow"
    bimba2 = Car.find_by_kind_and_name "Compact", "Bimba"
    assert_equal bimba, bimba2
    assert_equal "Yellow", bimba2.color
    bimba2 = Car.find_by_name_and_kind "Bimba", "Compact"
    assert_equal bimba, bimba2
    assert_equal "Yellow", bimba2.color
    bimba2 = Car.find_by_kind "Compact"
    assert_equal bimba, bimba2
    assert_equal "Yellow", bimba2.color
    cars = Car.find_all_by_color "Yellow"
    assert_equal 2, cars.size
    cars = Car.find_all_by_kind "Compact"
    assert_equal 1, cars.size
    bimba2 = Car.find_by_kind_and_color_and_name "Compact", "Yellow", "Bimba"
    assert_equal bimba, bimba2
    assert_equal "Yellow", bimba2.color
    assert_equal "Compact", bimba2.kind
    cars_before_creation = Car.count
    susita = Car.find_or_create_by_name_and_kind_and_color(\
        "Susita", "Compact", "Gray")
    assert_equal "Gray", susita.color
    assert_equal "Compact", susita.kind
    assert_equal cars_before_creation + 1, Car.count
    bimba2 = Car.find_or_create_by_name_and_kind_and_color(\
        "Bimba", "Compact", "Yellow")
    assert_equal "Yellow", bimba2.color
    assert_equal "Compact", bimba2.kind
    assert_equal "Bimba", bimba2.name
    assert_equal cars_before_creation + 1, Car.count
    p Car.all
    f16 = Plane.find_or_create_by_kind_and_name "Fighter Jet", "F-16"
    assert_equal "Fighter Jet", f16.kind
    assert_equal "F-16", f16.name
    ferrari = Car.find_or_create_by_kind_and_color "Sports", "Yellow"
    assert_equal "Yellow", ferrari.color
    assert_equal "Sports", ferrari.kind
    assert_equal cars_before_creation + 1, Car.count
    batmobile = Car.find_or_create_by_kind_and_color "Fantasy", "Black"
    assert_equal "Black", batmobile.color
    assert_equal "Fantasy", batmobile.kind
    assert_equal cars_before_creation + 2, Car.count
    assert_equal 3, CarKind.count
    assert_equal 3, CarColor.count
    assert_equal 1, PlaneKind.count
    batmobile2 = Car.find_or_initialize_by_color "Black"
    refute batmobile.new_record?
    assert_equal batmobile, batmobile2
    batmobile2 = Car.find_or_initialize_by_color_and_kind "Black", "Fantasy"
    refute batmobile.new_record?
    assert_equal batmobile, batmobile2
    bimba2 = Car.find_or_initialize_by_name "Bimba"
    refute bimba2.new_record?
    assert_equal bimba, bimba2
    delorhean = Car.find_or_initialize_by_color_and_kind "Grey", "Fantasy"
    assert delorhean.new_record?
    assert_equal "Grey", delorhean.color
    assert_equal "Fantasy", delorhean.kind
    delorhean.save!
  end

  #This test will issue warnings as we re-set existing constants
  def test_preload_caches
    #We have to define a new ActiveRecord class for this
    CarKind.create! name: "Compact"
    CarKind.create! name: "Sports"
    assert_nil CarKind.id_for("Compact")
    assert_nil CarKind.id_for("Sports")
    #We get a new CarKind class - but this one will be preloaded
    tmp = CarKind
    Class.new(ActiveRecord::Base) do
      include RailsLookup
      lookup :car_kind
    end
    refute_nil CarKind.id_for("Compact")
    refute_nil CarKind.id_for("Sports")
    refute_equal CarKind.id_for("Compact"), CarKind.id_for("Sports")
    assert_equal "Compact", CarKind.name_for(CarKind.id_for("Compact"))
    assert_equal "Sports", CarKind.name_for(CarKind.id_for("Sports"))
    #Revert to the old class
    #Object.const_set "CarKind", tmp
  end

  def test_where
    bimba = Car.create! :name => "Bimba", :kind => "Compact", :color => "Yellow"
    ferrari = Car.create! :kind => "Sports", :color => "Yellow"
    assert_equal 1, Car.where(kind: "Compact").count
    assert_equal 2, Car.where(color: "Yellow").count
    assert_equal 0, Car.where(color: "Red").count
    assert_equal 1, Car.where(color: "Yellow", kind: "Compact").count
    assert_equal 1, Car.where(name: "Bimba", kind: "Compact").count
  end

  #TODO: This currently fails
  def test_belongs_to
    bimba = Car.create! :name => "Bimba", :kind => "Compact", :color => "Yellow"
    ferrari = Car.create! :kind => "Sports", :color => "Yellow"
#    yellow = CarColor.find_by_name "Yellow"
#    assert_equal 2, yellow.cars.size
  end

  # TODO: Test a scope
  def test_scopes
    bimba = Car.create! :name => "Bimba", :kind => "Compact", :color => "Yellow"
    ferrari = Car.create! :kind => "Sports", :color => "Red"
    assert_equal 1, Car.by_color("Yellow").count 
    assert_equal 1, Car.by_color("Red").count
  end
end

