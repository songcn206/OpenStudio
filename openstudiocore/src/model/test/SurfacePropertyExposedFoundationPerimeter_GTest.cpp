/***********************************************************************************************************************
 *  OpenStudio(R), Copyright (c) 2008-2017, Alliance for Sustainable Energy, LLC. All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
 *  following conditions are met:
 *
 *  (1) Redistributions of source code must retain the above copyright notice, this list of conditions and the following
 *  disclaimer.
 *
 *  (2) Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
 *  following disclaimer in the documentation and/or other materials provided with the distribution.
 *
 *  (3) Neither the name of the copyright holder nor the names of any contributors may be used to endorse or promote
 *  products derived from this software without specific prior written permission from the respective party.
 *
 *  (4) Other than as required in clauses (1) and (2), distributions in any form of modifications or other derivative
 *  works may not use the "OpenStudio" trademark, "OS", "os", or any other confusingly similar designation without
 *  specific prior written permission from Alliance for Sustainable Energy, LLC.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 *  INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER, THE UNITED STATES GOVERNMENT, OR ANY CONTRIBUTORS BE LIABLE FOR
 *  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 *  AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **********************************************************************************************************************/

#include <gtest/gtest.h>

#include "ModelFixture.hpp"

#include "../Model.hpp"
#include "../Model_Impl.hpp"

#include "../SurfacePropertyExposedFoundationPerimeter.hpp"
#include "../SurfacePropertyExposedFoundationPerimeter_Impl.hpp"

#include "../Surface.hpp"
#include "../Surface_Impl.hpp"

using namespace openstudio;
using namespace openstudio::model;

TEST_F(ModelFixture, SurfacePropertyExposedFoundationPerimeter_SurfacePropertyExposedFoundationPerimeter) {
  ::testing::FLAGS_gtest_death_test_style = "threadsafe";

  ASSERT_EXIT(
    {
      // create a model to use
      Model model;

      // create a surface object to use
      Point3dVector points;
      points.clear();
      points.push_back(Point3d(0, 2, 0));
      points.push_back(Point3d(0, 0, 0));
      points.push_back(Point3d(1, 0, 0));      
      Surface surface(points, model);
      
      exit(0);
    },
    ::testing::ExitedWithCode(0),
    ""
  );
    
  // create a model to use
  Model model;
  
  // create a surface object to use
  Point3dVector points;
  points.clear();
  points.push_back(Point3d(0, 2, 0));
  points.push_back(Point3d(0, 0, 0));
  points.push_back(Point3d(1, 0, 0));
  Surface surface(points, model);
  EXPECT_EQ(1, model.modelObjects().size());
  
  // new surface does not have surface property exposed foundation perimeter yet
  EXPECT_TRUE(!surface.surfacePropertyExposedFoundationPerimeter());

  // create a surface property exposed foundation perimeter object to use
  boost::optional<SurfacePropertyExposedFoundationPerimeter> optprop = material.createSurfacePropertyExposedFoundationPerimeter("TotalExposedPerimeter");
  ASSERT_TRUE(optprop);
  EXPECT_EQ(2, model.modelObjects().size());

  // now the surface has surface property exposed foundation perimeter
  EXPECT_TRUE(surface.surfacePropertyExposedFoundationPerimeter());
  
  // check to make sure the exposed perimeter fraction field is defaulted as expected
  auto prop = optprop.get();
  EXPECT_TRUE(prop.isExposedPerimeterFractionDefaulted());

  // check that creating the surface property exposed foundation perimeter when they already exists does nothing and returns nil
  boost::optional<SurfacePropertyExposedFoundationPerimeter> optprop2 = material.createSurfacePropertyExposedFoundationPerimeter("TotalExposedPerimeter");
  ASSERT_FALSE(optprop2);
  EXPECT_EQ(2, model.modelObjects().size());
}

// test setting and getting
TEST_F(ModelFixture, SurfacePropertyExposedFoundationPerimeter_SetGetFields) {
  Model model;
  Point3dVector points;
  points.clear();
  points.push_back(Point3d(0, 2, 0));
  points.push_back(Point3d(0, 0, 0));
  points.push_back(Point3d(1, 0, 0));
  Surface surface(points, model);
  boost::optional<SurfacePropertyExposedFoundationPerimeter> optprop = surface.createSurfacePropertyExposedFoundationPerimeter("TotalExposedPerimeter");
  auto prop = optprop.get();

  // check that the perimeter properties were set properly
  EXPECT_EQ("TotalExposedPerimeter", prop.exposedPerimeterCalculationMethod());
  boost::optional<double> opttotalexposedperimeter = prop.totalExposedPerimeter();
  EXPECT_TRUE(opttotalexposedperimeter);
  auto totalexposedperimeter = opttotalexposedperimeter.get();
  EXPECT_EQ(10, totalexposedperimeter);
  ASSERT_TRUE(prop.isExposedPerimeterFractionDefaulted());
  EXPECT_EQ(1, prop.exposedPerimeterFraction());

  // now override the defaults with explicit values
  prop.setExposedPerimeterCalculationMethod("ExposedPerimeterFraction");
  prop.setTotalExposedPerimeter(15);
  prop.setExposedPerimeterFraction(0.8);

  EXPECT_EQ("ExposedPerimeterFraction", prop.exposedPerimeterCalculationMethod());
  boost::optional<double> opttotalexposedperimeter = prop.totalExposedPerimeter();
  EXPECT_TRUE(opttotalexposedperimeter);
  auto totalexposedperimeter = opttotalexposedperimeter.get();
  EXPECT_EQ(15, totalexposedperimeter);
  ASSERT_FALSE(prop.isExposedPerimeterFractionDefaulted());
  EXPECT_EQ(0.8, prop.exposedPerimeterFraction());

  // test setting back to defaults
  prop.resetExposedPerimeterFraction();
  ASSERT_TRUE(prop.isExposedPerimeterFractionDefaulted());
  EXPECT_EQ(1, prop.exposedPerimeterFraction());
}

// check that parent reset works
TEST_F(ModelFixture, SurfacePropertyExposedFoundationPerimeter_ParentReset) {

}

// check that parent remove works
TEST_F(ModelFixture, SurfacePropertyExposedFoundationPerimeter_ParentRemove) {

}

// check that child remove works
TEST_F(ModelFixture, SurfacePropertyExposedFoundationPerimeter_ChildRemove) {

}

// check that it points to the surface
TEST_F(ModelFixture, SurfacePropertyExposedFoundationPerimeter_MaterialName) {

}