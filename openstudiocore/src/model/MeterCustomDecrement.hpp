/**********************************************************************
 *  Copyright (c) 2008-2016, Alliance for Sustainable Energy.
 *  All rights reserved.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 **********************************************************************/

#ifndef MODEL_METERCUSTOMDECREMENT_HPP
#define MODEL_METERCUSTOMDECREMENT_HPP

#include "ModelAPI.hpp"
#include "ModelObject.hpp"

//#include <memory>

namespace openstudio {
namespace model {

namespace detail {

  class MeterCustomDecrement_Impl;

} // detail

/** MeterCustomDecrement is a ModelObject that wraps the OpenStudio IDD object 'OS:Meter:Custom'. */
class MODEL_API MeterCustomDecrement : public ModelObject {
 public:
  /** @name Constructors and Destructors */
  //@{

  // Constructs a new MeterCustomDecrement object in the model.
  explicit MeterCustomDecrement(const Model& model, const std::string& sourceMeterName);

  virtual ~MeterCustomDecrement() {}

  //@}

  static IddObjectType iddObjectType();

  static std::vector<std::string> fuelTypeValues();

  /** @name Getters */
  //@{

  boost::optional<std::string> fuelType() const;
  
  std::string sourceMeterName() const;

  // Return a vector of (Key, Var) pairs
  std::vector< std::pair<std::string, std::string> > keyVarGroups();

  // Return the number of (KeyName, OutputVariableorMeterName) groups
  unsigned numKeyVarGroups() const;


  // Lower Level functions
  /** Get the Key Name at index. Indexing starts at 0. */
  boost::optional<std::string> keyName(unsigned index) const;

  /** Get the Output Variable of Meter Name at index. Indexing starts at 0. */
  boost::optional<std::string> outputVariableorMeterName(unsigned index) const;

  //@}
  /** @name Setters */
  //@{

  bool setFuelType(const std::string& fuelType);

  void resetFuelType();
  
  bool setSourceMeterName(const std::string& sourceMeterName);

  // Add a new (Key, Var) group
  bool addKeyVarGroup(const std::string& keyName, const std::string& outputVariableorMeterName);

  // Remove the (Key, Var) group at given index
  bool removeKeyVarGroup(unsigned groupIndex);

  // Remove all the (Key, Var) groups
  void removeAllKeyVarGroups();


  // Lower level functions
  /** Set the Key Name at index. Indexing starts at 0. */
  bool setKeyName(unsigned index, const std::string& str);

  /** Set the Output Variable of Meter Name at index. Indexing starts at 0. */
  bool setOutputVariableorMeterName(unsigned index, const std::string& str);

  //@}
  /** @name Other */
  //@{

  //@}
  /** @name Type Casting */
  //@{


  //@}
 protected:
  /// @cond
  typedef detail::MeterCustomDecrement_Impl ImplType;

  explicit MeterCustomDecrement(std::shared_ptr<detail::MeterCustomDecrement_Impl> impl);

  friend class detail::MeterCustomDecrement_Impl;
  friend class Model;
  friend class IdfObject;
  friend class openstudio::detail::IdfObject_Impl;
  /// @endcond
 private:
  std::shared_ptr<detail::MeterCustomDecrement_Impl> m_impl;

  REGISTER_LOGGER("openstudio.model.MeterCustomDecrement");
};

/** \relates MeterCustomDecrement*/
typedef boost::optional<MeterCustomDecrement> OptionalMeterCustomDecrement;

/** \relates MeterCustomDecrement*/
typedef std::vector<MeterCustomDecrement> MeterCustomDecrementVector;

} // model
} // openstudio

#endif // MODEL_METERCUSTOMDECREMENT_HPP
