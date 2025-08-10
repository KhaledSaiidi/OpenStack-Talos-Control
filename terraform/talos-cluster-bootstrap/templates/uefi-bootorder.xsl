<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="xml" indent="yes"/>

  <!-- identity -->
  <xsl:template match="@*|node()">
    <xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy>
  </xsl:template>

  <!-- Ensure the FIRST NIC boots first AND is e1000e (UEFI PXE-friendly) -->
  <xsl:template match="/domain/devices/interface[1]">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <!-- add boot order -->
      <boot order="1"/>
      <!-- if model element did not exist, append one -->
      <xsl:if test="not(model)">
        <model type="e1000e"/>
      </xsl:if>
    </xsl:copy>
  </xsl:template>

  <!-- If a model element already exists on the first NIC, force it to e1000e -->
  <xsl:template match="/domain/devices/interface[1]/model">
    <model type="e1000e"/>
  </xsl:template>

  <!-- First actual disk (device='disk') boots second -->
  <xsl:template match="/domain/devices/disk[@device='disk'][1]">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <boot order="2"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
